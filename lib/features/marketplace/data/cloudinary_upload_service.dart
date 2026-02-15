import 'dart:async';
import 'dart:typed_data';

import 'package:cloudinary_public/cloudinary_public.dart';

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

  Future<String> uploadMarketplaceProductImageBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Selected image is empty.');
    }

    final cleanName = filename.trim().isEmpty ? 'image.jpg' : filename.trim();

    final file = CloudinaryFile.fromBytes(
      bytes,
      identifier: cleanName,
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
      final msg = e.message.trim();
      if (msg.isNotEmpty) {
        throw StateError('Upload failed: $msg');
      }
      throw StateError('Upload failed.');
    }
  }
}
