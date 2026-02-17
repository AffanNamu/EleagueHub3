import 'dart:async';
import 'dart:io';

import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:file_picker/file_picker.dart';

class CloudinaryUploadService {
  CloudinaryUploadService({
    String? cloudName,
    String? uploadPreset,
  })  : _cloudName =
            (cloudName ?? const String.fromEnvironment('CLOUDINARY_CLOUD_NAME'))
                .trim(),
        _uploadPreset = (uploadPreset ??
                const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET'))
            .trim();

  final String _cloudName;
  final String _uploadPreset;

  CloudinaryPublic _client({bool cache = false}) {
    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      throw StateError('Cloudinary is not configured.');
    }
    return CloudinaryPublic(
      _cloudName,
      _uploadPreset,
      cache: cache,
    );
  }

  Future<String> uploadMarketplaceProductImageFile({
    required String filePath,
  }) async {
    final path = filePath.trim();
    if (path.isEmpty) {
      throw StateError('Selected image path is not available.');
    }

    final file = CloudinaryFile.fromFile(
      path,
      folder: 'eleaguehub/marketplace_products',
      resourceType: CloudinaryResourceType.Image,
    );

    try {
      final res = await _client().uploadFile(file).timeout(
            const Duration(seconds: 60),
          );

      final secureUrl = res.secureUrl.trim();
      if (secureUrl.isEmpty) {
        throw StateError('Upload failed: secure_url missing.');
      }

      return secureUrl;
    } on TimeoutException {
      throw StateError('Upload timed out. Please try again.');
    } on CloudinaryException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) {
        throw StateError('Upload failed: $msg');
      }
      throw StateError('Upload failed.');
    }
  }

  /// Generic uploader for PlatformFile (SafeImagePicker output).
  ///
  /// - Uses existing UNSIGNED preset env: CLOUDINARY_UNSIGNED_UPLOAD_PRESET
  /// - Stores files under the provided [folder] (should start with `eleaguehub/`)
  /// - Returns Cloudinary secure_url (HTTPS)
  Future<String> uploadImagePlatformFile({
    required PlatformFile file,
    required String folder,
  }) async {
    final safeFolder = folder.trim();
    if (safeFolder.isEmpty) {
      throw StateError('Upload folder is required.');
    }

    // Enforce a conservative namespace (matches your worker sign route requirement too).
    if (!safeFolder.startsWith('eleaguehub/')) {
      throw StateError('Invalid upload folder (must start with eleaguehub/).');
    }

    final name = file.name.trim().isEmpty ? 'image.jpg' : file.name.trim();
    final path = (file.path ?? '').trim();
    final bytes = file.bytes;

    File? tmp;
    String uploadPath = path;

    try {
      if (uploadPath.isEmpty) {
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Selected image is not available.');
        }

        // Some pickers return bytes without a path; write to a temp file (mobile-safe).
        final dir = Directory.systemTemp;
        final tmpPath = '${dir.path}/eleaguehub_${DateTime.now().millisecondsSinceEpoch}_$name';
        tmp = File(tmpPath);
        await tmp.writeAsBytes(bytes, flush: true).timeout(const Duration(seconds: 10));
        uploadPath = tmp.path;
      }

      final cloudFile = CloudinaryFile.fromFile(
        uploadPath,
        folder: safeFolder,
        resourceType: CloudinaryResourceType.Image,
      );

      final res = await _client().uploadFile(cloudFile).timeout(const Duration(seconds: 60));

      final secureUrl = res.secureUrl.trim();
      if (secureUrl.isEmpty) {
        throw StateError('Upload failed: secure_url missing.');
      }
      return secureUrl;
    } on TimeoutException {
      throw StateError('Upload timed out. Please try again.');
    } on CloudinaryException catch (e) {
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) throw StateError('Upload failed: $msg');
      throw StateError('Upload failed.');
    } finally {
      try {
        if (tmp != null && await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
    }
  }

  /// Chat helper: keeps folder policy in one place.
  Future<String> uploadChatImage({
    required PlatformFile file,
    required String folder,
  }) {
    return uploadImagePlatformFile(file: file, folder: folder);
  }
}
