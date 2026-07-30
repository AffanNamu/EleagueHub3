import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

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

  /// Generic uploader for audio/video files (Cloudinary treats audio as "video").
  ///
  /// Requirements implemented:
  /// - Uses SAME Cloudinary cloud name + unsigned preset (env-based) as existing uploads
  /// - Upload folder is NOT restricted to `eleaguehub/` so we can support:
  ///   chat_voice_messages/{leagueId}/{timestamp}.m4a
  /// - resource_type is forced to VIDEO (required for audio)
  /// - Returns secure_url
  Future<String> uploadAudioPlatformFileAsVideo({
    required PlatformFile file,
    required String folder,
  }) async {
    final safeFolder = folder.trim();
    if (safeFolder.isEmpty) {
      throw StateError('Upload folder is required.');
    }

    final name = file.name.trim().isEmpty ? 'audio.m4a' : file.name.trim();
    final path = (file.path ?? '').trim();
    final bytes = file.bytes;

    File? tmp;
    String uploadPath = path;

    try {
      if (uploadPath.isEmpty) {
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Selected audio is not available.');
        }

        final dir = Directory.systemTemp;
        final tmpPath = '${dir.path}/eleaguehub_${DateTime.now().millisecondsSinceEpoch}_$name';
        tmp = File(tmpPath);
        await tmp.writeAsBytes(bytes, flush: true).timeout(const Duration(seconds: 10));
        uploadPath = tmp.path;
      }

      final cloudFile = CloudinaryFile.fromFile(
        uploadPath,
        folder: safeFolder,
        resourceType: CloudinaryResourceType.Video, // required for audio
      );

      final res = await _client().uploadFile(cloudFile).timeout(const Duration(seconds: 90));

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

  /// Chat helper: voice uploader (Cloudinary audio-as-video).
  Future<String> uploadChatVoice({
    required PlatformFile file,
    required String folder,
  }) {
    return uploadAudioPlatformFileAsVideo(file: file, folder: folder);
  }

  /// Re-hosts a REMOTE image URL (e.g. a third-party sports-photo API
  /// result) under our own Cloudinary cloud. Unlike the other upload
  /// methods, this never touches the device's filesystem or downloads
  /// bytes into the app — Cloudinary fetches [sourceUrl] server-side.
  /// Used so the app never hotlinks third-party APIs directly, and so
  /// the resulting URL benefits from the same CDN/caching/optimization
  /// as every other Cloudinary-hosted image in the app.
  ///
  /// - [folder] must start with `eleaguehub/`, same policy as
  ///   [uploadImagePlatformFile].
  /// - Returns '' (does not throw) if [sourceUrl] is empty, so callers
  ///   can treat "no photo found" as a normal, non-error outcome.
  Future<String> uploadRemoteImageUrl({
    required String sourceUrl,
    required String folder,
  }) async {
    final url = sourceUrl.trim();
    if (url.isEmpty) return '';

    final safeFolder = folder.trim();
    if (safeFolder.isEmpty) {
      throw StateError('Upload folder is required.');
    }
    if (!safeFolder.startsWith('eleaguehub/')) {
      throw StateError('Invalid upload folder (must start with eleaguehub/).');
    }
    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      throw StateError('Cloudinary is not configured.');
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final uploadUrl = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['file'] = url
      ..fields['upload_preset'] = _uploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = safeFolder
      ..fields['public_id'] = 'remote_$ts';

    try {
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 30));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // A single failed remote fetch (dead link, rate limit, etc.)
        // shouldn't block the whole save flow — treat as "no photo".
        return '';
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return '';

      final secureUrl = (decoded['secure_url']?.toString() ?? '').trim();
      return secureUrl;
    } on TimeoutException {
      return '';
    } catch (_) {
      return '';
    }
  }
}
