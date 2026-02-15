import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Crash-safe image picker for ALL Android versions.
///
/// FilePicker uses SAF on Android 10+ — no runtime permission needed.
/// The crash on Huawei EMUI 10 is caused by Activity being destroyed
/// while picker is open, then Flutter engine state is lost on return.
///
/// This class wraps FilePicker with:
/// - Full try-catch (never throws)
/// - Two-attempt strategy (withData → path-only fallback)
/// - Bytes read from File if picker returns null bytes
/// - User-friendly error messages
class SafeImagePicker {
  SafeImagePicker._();

  static const int maxBytes = 5 * 1024 * 1024;

  /// Pick a single image. NEVER throws. Returns [SafePickResult].
  static Future<SafePickResult> pickImage() async {
    // ── Attempt 1: withData=true ──
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

      // bytes null but path exists — read bytes from cached file
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

        // Return with path only — upload will use fromPath
        return SafePickResult.success(picked);
      }

      // No bytes, no path — fall through to attempt 2
    } on PlatformException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (_isCancelMessage(msg)) return SafePickResult.cancelled();
    } on TimeoutException {
      return SafePickResult.error('Image picker timed out. Please try again.');
    } catch (e) {
      if (_isCancelMessage(e.toString().toLowerCase())) {
        return SafePickResult.cancelled();
      }
    }

    // ── Attempt 2: withData=false (path only) ──
    try {
      final result = await FilePicker.platform
          .pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: false,
            withReadStream: false,
            lockParentWindow: false,
          )
          .timeout(const Duration(seconds: 120));

      if (result == null || result.files.isEmpty) {
        return SafePickResult.cancelled();
      }

      final picked = result.files.first;

      if (picked.size > maxBytes) {
        return SafePickResult.error('Image is too large. Maximum allowed is 5 MB.');
      }

      final path = (picked.path ?? '').trim();
      if (path.isEmpty) {
        return SafePickResult.error(
          'Could not access the selected image. '
          'Please try a different image or folder.',
        );
      }

      // Try to read bytes from path
      try {
        final file = File(path);
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
                path: path,
              ),
            );
          }
        }
      } catch (_) {}

      // Return with path only
      return SafePickResult.success(picked);
    } on PlatformException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (_isCancelMessage(msg)) return SafePickResult.cancelled();
      return SafePickResult.error(
        'Could not open image picker. Please restart the app and try again.',
      );
    } on TimeoutException {
      return SafePickResult.error('Image picker timed out. Please try again.');
    } catch (_) {
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
