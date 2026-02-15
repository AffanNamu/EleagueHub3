import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Crash-safe image picker for ALL Android versions.
///
/// PRIMARY: Uses image_picker (native photo picker) — lightweight, no crash.
/// FALLBACK: Uses file_picker if image_picker fails for any reason.
class SafeImagePicker {
  SafeImagePicker._();

  static const int maxBytes = 5 * 1024 * 1024;

  static final ImagePicker _imagePicker = ImagePicker();

  /// Pick a single image. NEVER throws. Returns [SafePickResult].
  static Future<SafePickResult> pickImage() async {
    // ── PRIMARY: image_picker (native gallery — no crash) ──
    try {
      final XFile? xFile = await _imagePicker
          .pickImage(
            source: ImageSource.gallery,
            maxWidth: 1200,
            maxHeight: 1200,
            imageQuality: 85,
          )
          .timeout(const Duration(seconds: 120));

      if (xFile == null) {
        return SafePickResult.cancelled();
      }

      final file = File(xFile.path);

      if (!await file.exists()) {
        return SafePickResult.error(
          'Selected image file not found. Please try again.',
        );
      }

      final fileSize = await file.length();

      if (fileSize > maxBytes) {
        return SafePickResult.error(
          'Image is too large (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Maximum allowed is 5 MB.',
        );
      }

      if (fileSize == 0) {
        return SafePickResult.error(
          'Selected file appears to be empty. Please choose a different image.',
        );
      }

      try {
        final Uint8List bytes = await file.readAsBytes().timeout(
              const Duration(seconds: 15),
            );

        if (bytes.isNotEmpty) {
          final platformFile = PlatformFile(
            name: xFile.name.isNotEmpty ? xFile.name : 'profile_image.jpg',
            size: bytes.length,
            bytes: bytes,
            path: xFile.path,
          );
          return SafePickResult.success(platformFile);
        }
      } catch (_) {}

      final platformFile = PlatformFile(
        name: xFile.name.isNotEmpty ? xFile.name : 'profile_image.jpg',
        size: fileSize,
        bytes: null,
        path: xFile.path,
      );
      return SafePickResult.success(platformFile);
    } on TimeoutException {
      return SafePickResult.error('Image picker timed out. Please try again.');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (_isCancelMessage(msg)) {
        return SafePickResult.cancelled();
      }
    }

    // ── FALLBACK: file_picker ──
    try {
      final result = await FilePicker.platform
          .pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
            withReadStream: false,
            lockParentWindow: false,
          )
          .timeout(const Duration(seconds: 120));

      if (result == null || result.files.isEmpty) {
        return SafePickResult.cancelled();
      }

      final picked = result.files.first;

      if (picked.size > maxBytes) {
        return SafePickResult.error(
          'Image is too large (${(picked.size / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Maximum allowed is 5 MB.',
        );
      }

      if (picked.size == 0) {
        return SafePickResult.error(
          'Selected file appears to be empty. Please choose a different image.',
        );
      }

      final hasBytes = picked.bytes != null && picked.bytes!.isNotEmpty;
      final hasPath = (picked.path ?? '').trim().isNotEmpty;

      if (hasBytes) {
        return SafePickResult.success(picked);
      }

      if (hasPath) {
        try {
          final file = File(picked.path!.trim());
          if (await file.exists()) {
            final bytes = await file.readAsBytes().timeout(
                  const Duration(seconds: 15),
                );
            if (bytes.isNotEmpty) {
              return SafePickResult.success(
                PlatformFile(
                  name: picked.name,
                  size: bytes.length,
                  bytes: bytes,
                  path: picked.path,
                ),
              );
            }
          }
        } catch (_) {}

        return SafePickResult.success(picked);
      }

      return SafePickResult.error(
        'Could not read the selected image. Please try a different image.',
      );
    } on TimeoutException {
      return SafePickResult.error('Image picker timed out. Please try again.');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (_isCancelMessage(msg)) {
        return SafePickResult.cancelled();
      }
      return SafePickResult.error(
        'Could not open image picker. Please restart the app and try again.',
      );
    }
  }

  static bool _isCancelMessage(String msg) {
    return msg.contains('cancel') ||
        msg.contains('user') ||
        msg.contains('abort') ||
        msg.contains('dismissed');
  }
}

class SafePickResult {
  final PlatformFile? file;
  final String? errorMessage;
  final bool wasCancelled;

  const SafePickResult._({
    this.file,
    this.errorMessage,
    this.wasCancelled = false,
  });

  factory SafePickResult.success(PlatformFile file) =>
      SafePickResult._(file: file);

  factory SafePickResult.error(String message) =>
      SafePickResult._(errorMessage: message);

  factory SafePickResult.cancelled() =>
      const SafePickResult._(wasCancelled: true);

  bool get isSuccess => file != null && errorMessage == null && !wasCancelled;
}
