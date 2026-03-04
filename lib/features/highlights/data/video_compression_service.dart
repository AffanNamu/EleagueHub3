import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Probe info extracted via FFprobe (no network required).
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
/// - Forces H.264 + AAC
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

  /// Probes duration + dimensions.
  Future<VideoProbeInfo> probe(String inputPath) async {
    final p = inputPath.trim();
    if (p.isEmpty) {
      throw StateError('Video path is empty.');
    }

    final f = File(p);
    if (!await f.exists()) {
      throw StateError('Video file not found.');
    }

    final session = await FFprobeKit.getMediaInformation(p);
    final info = session.getMediaInformation();

    if (info == null) {
      throw StateError('Could not read video information.');
    }

    final durationRaw = (info.getDuration() ?? '').trim();
    final durationSeconds = double.tryParse(durationRaw) ?? 0;

    int width = 0;
    int height = 0;

    final streams = info.getStreams() ?? <dynamic>[];
    Map<String, dynamic>? videoProps;

    for (final s in streams) {
      try {
        final type = (s.getType() ?? '').toString().toLowerCase();
        if (type != 'video') continue;

        final props = (s.getAllProperties() ?? <String, dynamic>{}).cast<String, dynamic>();
        videoProps = props;
        break;
      } catch (_) {
        continue;
      }
    }

    if (videoProps != null) {
      width = _intFrom(videoProps['width']);
      height = _intFrom(videoProps['height']);

      if (width <= 0) width = _intFrom(videoProps['coded_width']);
      if (height <= 0) height = _intFrom(videoProps['coded_height']);
    }

    final format = info.getFormat();

    return VideoProbeInfo(
      durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
      width: max(0, width),
      height: max(0, height),
      format: format?.trim().isEmpty == true ? null : format?.trim(),
    );
  }

  /// Compresses a selected video to meet highlight constraints.
  ///
  /// [onProgress] emits 0..1 based on encoded time / duration.
  Future<CompressedVideoResult> compressHighlight({
    required String inputPath,
    int maxDurationSec = maxDurationSeconds,
    int maxBytes = maxOutputBytes,
    int maxHeight = maxOutputHeight,
    void Function(double progress01)? onProgress,
  }) async {
    final input = inputPath.trim();
    if (input.isEmpty) throw StateError('Video path is empty.');

    final inputFile = File(input);
    if (!await inputFile.exists()) throw StateError('Video file not found.');

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

    final dur = inputInfo.durationSeconds;
    final maxTotalKbps = ((maxBytes * 8) / dur / 1000).floor();

    var videoKbps = max(250, maxTotalKbps - audioBitrateKbps - containerOverheadKbps);
    videoKbps = videoKbps.clamp(350, 2200);

    final effectiveMaxHeight = (videoKbps < 900) ? 540 : maxHeight;

    final vf = "scale=-2:'min(ih\\,$effectiveMaxHeight)',setsar=1";

    final cmd = [
      '-y',
      '-i',
      _q(input),
      '-vf',
      _q(vf),
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-pix_fmt',
      'yuv420p',
      '-profile:v',
      'main',
      '-b:v',
      '${videoKbps}k',
      '-maxrate',
      '${(videoKbps * 1.20).round()}k',
      '-bufsize',
      '${(videoKbps * 2.00).round()}k',
      '-c:a',
      'aac',
      '-b:a',
      '${audioBitrateKbps}k',
      '-ac',
      '2',
      '-ar',
      '44100',
      '-movflags',
      '+faststart',
      _q(outPath),
    ].join(' ');

    double lastProgress = 0;

    try {
      final completer = Completer<void>();

      await FFmpegKit.executeAsync(
        cmd,
        (session) async {
          final rc = await session.getReturnCode();
          if (ReturnCode.isSuccess(rc)) {
            completer.complete();
          } else {
            final logs = await session.getAllLogsAsString();
            completer.completeError(
              StateError('Compression failed. ${_bestEffortLogHint(logs)}'),
            );
          }
        },
        null,
        (stats) {
          final tMs = stats.getTime();
          if (tMs <= 0) return;

          final p = (tMs / (dur * 1000)).clamp(0.0, 1.0);
          if (p <= lastProgress) return;
          lastProgress = p;

          if (onProgress != null) onProgress(p);
        },
      );

      await completer.future.timeout(const Duration(minutes: 6));

      final outFile = File(outPath);
      if (!await outFile.exists()) {
        throw StateError('Compression failed: output file missing.');
      }

      final outBytes = await outFile.length();
      if (outBytes <= 0) {
        throw StateError('Compression failed: output is empty.');
      }

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
    } on TimeoutException {
      try {
        final out = File(outPath);
        if (await out.exists()) await out.delete();
      } catch (_) {}
      throw StateError('Compression timed out. Please try again.');
    } catch (e) {
      try {
        final out = File(outPath);
        if (await out.exists()) await out.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static int _intFrom(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static String _q(String s) {
    final v = s.replaceAll('"', '\\"');
    return '"$v"';
  }

  static String _bestEffortLogHint(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    final lines = s.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '';
    return lines.length <= 3 ? lines.join(' ') : lines.sublist(max(0, lines.length - 3)).join(' ');
  }
}
