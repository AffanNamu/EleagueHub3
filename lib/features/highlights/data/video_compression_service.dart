import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Probe info extracted natively (no network required).
class VideoProbeInfo {
  final double durationSeconds;
  final int width;
  final int height;
  final String? format;

  const VideoProbeInfo({
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.format,
  });
}

/// Output of highlight compression step.
class CompressedVideoResult {
  final String outputPath;
  final int outputBytes;
  final VideoProbeInfo inputInfo;

  /// Encoder settings used (useful for debugging and future tuning).
  final int targetMaxHeight;
  final int videoBitrateKbps;
  final int audioBitrateKbps;

  const CompressedVideoResult({
    required this.outputPath,
    required this.outputBytes,
    required this.inputInfo,
    required this.targetMaxHeight,
    required this.videoBitrateKbps,
    required this.audioBitrateKbps,
  });
}

/// Ultra-low-cost highlight compression policy:
/// - Hard caps duration (reject if over limit)
/// - Forces H.264 + AAC (native Android transcode)
/// - Downscales to <= 720p (and may go lower to respect 15MB cap)
/// - Targets a bitrate computed from size cap so we don't exceed free-tier storage/bandwidth
///
/// IMPORTANT COST RULE:
/// - We intentionally avoid Cloudinary transformations/derived assets by compressing client-side.
/// - This is CPU-expensive on the device, but it is zero-infra cost and saves Cloudinary usage.
class VideoCompressionService {
  static const int maxOutputBytes = 15 * 1024 * 1024; // 15MB hard cap (policy)
  static const int maxDurationSeconds = 180; // 3 minutes hard cap (policy)
  static const int maxOutputHeight = 720;

  /// Audio policy: keep AAC at 128kbps when possible (requirement).
  static const int audioBitrateKbps = 128;

  /// A small overhead budget for container + moov atom etc.
  static const int containerOverheadKbps = 48;

  static const MethodChannel _ch = MethodChannel('highlight_compression');
  static const EventChannel _progressCh = EventChannel('highlight_compression_progress');

  /// Probes duration + dimensions.
  Future<VideoProbeInfo> probe(String inputPath) async {
    final p = inputPath.trim();
    if (p.isEmpty) {
      throw StateError('Video path is empty.');
    }

    final f = File(p);
    if (!await f.exists()) {
      // Some pickers can return content:// URIs (no direct file path).
      // If it's a content URI, skip this exists check.
      if (!p.startsWith('content://') && !p.startsWith('file://')) {
        throw StateError('Video file not found.');
      }
    }

    if (!Platform.isAndroid) {
      throw UnsupportedError('Video probing is currently implemented for Android only.');
    }

    final res = await _ch.invokeMethod<dynamic>(
      'probe',
      <String, dynamic>{'inputPath': p},
    );

    if (res is! Map) {
      throw StateError('Probe failed: invalid response.');
    }

    final map = res.cast<dynamic, dynamic>();

    final duration = (map['durationSeconds'] is num) ? (map['durationSeconds'] as num).toDouble() : 0.0;
    final width = (map['width'] is num) ? (map['width'] as num).toInt() : 0;
    final height = (map['height'] is num) ? (map['height'] as num).toInt() : 0;
    final format = (map['format'] as String?)?.trim();
    final fmt = (format != null && format.isNotEmpty) ? format : null;

    return VideoProbeInfo(
      durationSeconds: duration.isFinite ? duration : 0.0,
      width: max(0, width),
      height: max(0, height),
      format: fmt,
    );
  }

  /// Compresses a selected video to meet highlight constraints.
  ///
  /// [onProgress] emits 0..1 best-effort (native progress polling).
  Future<CompressedVideoResult> compressHighlight({
    required String inputPath,
    int maxDurationSec = maxDurationSeconds,
    int maxBytes = maxOutputBytes,
    int maxHeight = maxOutputHeight,
    void Function(double progress01)? onProgress,
  }) async {
    final input = inputPath.trim();
    if (input.isEmpty) throw StateError('Video path is empty.');

    if (!Platform.isAndroid) {
      throw UnsupportedError('Highlight compression is currently implemented for Android only.');
    }

    final inputInfo = await probe(input);

    if (inputInfo.durationSeconds <= 0) {
      throw StateError('Could not determine video duration.');
    }

    if (inputInfo.durationSeconds > maxDurationSec) {
      throw StateError(
        'Video is too long (${inputInfo.durationSeconds.toStringAsFixed(0)}s). '
        'Maximum allowed is $maxDurationSec seconds.',
      );
    }

    final tmpDir = await getTemporaryDirectory();
    final outPath = '${tmpDir.path}/highlight_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Compute a total bitrate ceiling from maxBytes & duration:
    final dur = inputInfo.durationSeconds;
    final maxTotalKbps = ((maxBytes * 8) / dur / 1000).floor();

    // Keep audio fixed, allocate remainder to video.
    var videoKbps = max(250, maxTotalKbps - audioBitrateKbps - containerOverheadKbps);

    // Conservative clamp for mobile stability.
    videoKbps = videoKbps.clamp(350, 2200);

    // If bitrate is low, downscale more (still <=720p max).
    final effectiveMaxHeight = (videoKbps < 900) ? 540 : maxHeight;

    final taskId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

    StreamSubscription<dynamic>? sub;
    if (onProgress != null) {
      try {
        sub = _progressCh.receiveBroadcastStream().listen((event) {
          if (event is! Map) return;
          final m = event.cast<dynamic, dynamic>();
          if (m['taskId']?.toString() != taskId) return;

          final p = (m['progress01'] is num) ? (m['progress01'] as num).toDouble() : 0.0;
          if (p.isNaN || !p.isFinite) return;
          onProgress(p.clamp(0.0, 1.0));
        });
      } catch (_) {
        // If event channel fails, compression still works; UI can show indeterminate progress.
      }
    }

    try {
      final res = await _ch.invokeMethod<dynamic>(
        'compress',
        <String, dynamic>{
          'taskId': taskId,
          'inputPath': input,
          'outputPath': outPath,
          'maxHeight': effectiveMaxHeight,
          'videoBitrateKbps': videoKbps,
          'audioBitrateKbps': audioBitrateKbps,
        },
      );

      if (res is! Map) {
        throw StateError('Compression failed: invalid response.');
      }

      final outFile = File(outPath);
      if (!await outFile.exists()) {
        throw StateError('Compression failed: output file missing.');
      }

      final outBytes = await outFile.length();
      if (outBytes <= 0) {
        throw StateError('Compression failed: output is empty.');
      }

      // HARD policy check: never upload a file over cap.
      if (outBytes > maxBytes) {
        try {
          await outFile.delete();
        } catch (_) {}

        throw StateError(
          'Compressed video is still too large (${(outBytes / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Maximum allowed is ${(maxBytes / 1024 / 1024).toStringAsFixed(0)} MB. '
          'Try a shorter clip or record in lower quality.',
        );
      }

      if (onProgress != null) onProgress(1);

      return CompressedVideoResult(
        outputPath: outPath,
        outputBytes: outBytes,
        inputInfo: inputInfo,
        targetMaxHeight: effectiveMaxHeight,
        videoBitrateKbps: videoKbps,
        audioBitrateKbps: audioBitrateKbps,
      );
    } on PlatformException catch (e) {
      // Best-effort cleanup.
      try {
        final out = File(outPath);
        if (await out.exists()) await out.delete();
      } catch (_) {}

      final msg = (e.message ?? '').trim();
      throw StateError(msg.isNotEmpty ? msg : 'Compression failed.');
    } on TimeoutException {
      try {
        final out = File(outPath);
        if (await out.exists()) await out.delete();
      } catch (_) {}
      throw StateError('Compression timed out. Please try again.');
    } catch (e) {
      // Best-effort cleanup.
      try {
        final out = File(outPath);
        if (await out.exists()) await out.delete();
      } catch (_) {}
      rethrow;
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
    }
  }
}
