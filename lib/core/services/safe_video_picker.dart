import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Crash-safe VIDEO picker for unstable Android devices + OEM gallery apps.
///
/// PRIMARY: image_picker (native) for best UX.
/// FALLBACK: file_picker if image_picker fails.
///
/// IMPORTANT:
/// - This picker enforces only "cheap" checks (existence + raw bytes size).
/// - Duration/resolution validation is enforced later via FFprobe before compression/upload.
/// - Final hard limits (<= 15MB, <= 720p, <= 2–3 minutes) are enforced in the highlight pipeline.
class SafeVideoPicker {
  SafeVideoPicker._();

  /// Hard safety ceiling for *input* file size to avoid abusive selections that would:
  /// - drain battery on compression,
  /// - crash low-memory devices,
  /// - waste user data on accidental huge files.
  ///
  /// The actual highlight policy is enforced on the OUTPUT (compressed) file.
  static const int maxInputBytes = 250 * 1024 * 1024; // 250MB

  /// Soft picker constraint. Authoritative duration validation is done via FFprobe later.
  static const int maxDurationSeconds = 180; // 3 minutes

  static final ImagePicker _picker = ImagePicker();

  /// Pick a single video. NEVER throws. Returns [SafeVideoPickResult].
  static Future<SafeVideoPickResult> pickVideo() async {
    // ── PRIMARY: image_picker ─────────────────────────────────────────────
    try {
      final XFile? xFile = await _picker
          .pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(seconds: maxDurationSeconds),
          )
          .timeout(const Duration(seconds: 120));

      if (xFile == null) return SafeVideoPickResult.cancelled();

      final file = File(xFile.path);
      if (!await file.exists()) {
        return SafeVideoPickResult.error('Selected video file not found. Please try again.');
      }

      final size = await file.length();
      if (size <= 0) {
        return SafeVideoPickResult.error('Selected video appears to be empty. Please choose a different video.');
      }

      if (size > maxInputBytes) {
        return SafeVideoPickResult.error(
          'Video is too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Please choose a shorter/smaller clip.',
        );
      }

      // Prefer bytes if quickly readable (some upload stacks prefer bytes-only).
      // But for video, keeping a path is typically better (no huge in-memory bytes).
      Uint8List? bytes;
      try {
        // Best-effort read cap: do NOT attempt to read huge videos into memory.
        // We only read bytes if reasonably small (< 35MB).
        if (size <= 35 * 1024 * 1024) {
          bytes = await file.readAsBytes().timeout(const Duration(seconds: 20));
          if (bytes.isEmpty) bytes = null;
        }
      } catch (_) {
        bytes = null;
      }

      return SafeVideoPickResult.success(
        PlatformFile(
          name: xFile.name.isNotEmpty ? xFile.name : 'highlight.mp4',
          size: size,
          bytes: bytes,
          path: xFile.path,
        ),
      );
    } on TimeoutException {
      return SafeVideoPickResult.error('Video picker timed out. Please try again.');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (_isCancelMessage(msg)) return SafeVideoPickResult.cancelled();
      // Fall through to fallback.
    }

    // ── FALLBACK: file_picker ─────────────────────────────────────────────
    try {
      final result = await FilePicker.platform
          .pickFiles(
            type: FileType.video,
            allowMultiple: false,
            withData: false, // avoid loading large videos into memory
            withReadStream: false,
            lockParentWindow: false,
          )
          .timeout(const Duration(seconds: 120));

      if (result == null || result.files.isEmpty) return SafeVideoPickResult.cancelled();

      final picked = result.files.first;

      final path = (picked.path ?? '').trim();
      if (path.isEmpty) {
        return SafeVideoPickResult.error('Could not access the selected video file. Please try a different video.');
      }

      final file = File(path);
      if (!await file.exists()) {
        return SafeVideoPickResult.error('Selected video file not found. Please try again.');
      }

      final size = await file.length();
      if (size <= 0) {
        return SafeVideoPickResult.error('Selected video appears to be empty. Please choose a different video.');
      }

      if (size > maxInputBytes) {
        return SafeVideoPickResult.error(
          'Video is too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Please choose a shorter/smaller clip.',
        );
      }

      return SafeVideoPickResult.success(
        PlatformFile(
          name: picked.name.trim().isNotEmpty ? picked.name.trim() : 'highlight.mp4',
          size: size,
          bytes: null,
          path: path,
        ),
      );
    } on TimeoutException {
      return SafeVideoPickResult.error('Video picker timed out. Please try again.');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (_isCancelMessage(msg)) return SafeVideoPickResult.cancelled();
      return SafeVideoPickResult.error(
        'Could not open video picker. Please restart the app and try again.',
      );
    }
  }

  static bool _isCancelMessage(String msg) {
    return msg.contains('cancel') || msg.contains('user') || msg.contains('abort') || msg.contains('dismissed');
  }
}

class SafeVideoPickResult {
  final PlatformFile? file;
  final String? errorMessage;
  final bool wasCancelled;

  const SafeVideoPickResult._({
    this.file,
    this.errorMessage,
    this.wasCancelled = false,
  });

  factory SafeVideoPickResult.success(PlatformFile file) => SafeVideoPickResult._(file: file);

  factory SafeVideoPickResult.error(String message) => SafeVideoPickResult._(errorMessage: message);

  factory SafeVideoPickResult.cancelled() => const SafeVideoPickResult._(wasCancelled: true);

  bool get isSuccess => file != null && errorMessage == null && !wasCancelled;
}
