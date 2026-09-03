//lib/features/chat/presentation/widgets/voice_message_player.dart
//
// WhatsApp-style voice message bubble:
// - Before download: shows duration (if known) and an explicit Download
//   action. Nothing is fetched automatically.
// - After download: a real local audio player — play/pause, seek bar,
//   position/duration, seek back/forward 10s, replay, resume from the
//   last playback position — all backed by a local file, so playback
//   never depends on network/Cloudinary availability once downloaded.
//
// Playback is coordinated through the app-wide ChatAudioPlaybackController
// singleton so only one voice message plays at a time, exactly like the
// per-screen AudioPlayer instances did before this redesign.

import 'package:flutter/material.dart';

import '../../../../core/services/chat_audio_playback_controller.dart';
import '../../../../core/services/chat_media_cache_service.dart';
import '../../../../core/theme/app_theme.dart';

class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.voiceUrl,
    this.durationMsHint,
    this.width = 240,
    this.iconColor,
    this.accentColor,
    this.trackColor,
    this.labelColor,
    this.caption,
  });

  /// The original Cloudinary voice-note URL.
  final String voiceUrl;

  /// Known duration from Firestore (`voiceDurationMs`), if the message was
  /// sent after this redesign. May be null/0 for older messages, in which
  /// case the duration shows as unknown until first played (at which point
  /// it's learned and cached locally for next time).
  final int? durationMsHint;

  final double width;
  final Color? iconColor;
  final Color? accentColor;
  final Color? trackColor;
  final Color? labelColor;
  final String? caption;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  int _resumeFromMs = 0;
  int? _knownDurationMs;

  @override
  void initState() {
    super.initState();
    _knownDurationMs = (widget.durationMsHint ?? 0) > 0 ? widget.durationMsHint : null;
    _loadResumeMetadata();
  }

  Future<void> _loadResumeMetadata() async {
    final cache = ChatMediaCacheService.instance;
    final pos = await cache.getPlaybackPositionMs(widget.voiceUrl);
    final dur = await cache.getVoiceDurationMs(widget.voiceUrl);
    if (!mounted) return;
    setState(() {
      _resumeFromMs = pos;
      if (dur != null && dur > 0) _knownDurationMs = dur;
    });
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _download(BuildContext context) async {
    try {
      await ChatMediaCacheService.instance.download(
        url: widget.voiceUrl,
        kind: ChatMediaKind.voice,
      );
      await _loadResumeMetadata();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final icon = widget.iconColor ?? AppTheme.limeAccentDark;
    final accent = widget.accentColor ?? AppTheme.limeAccentDark;
    final track = widget.trackColor ?? AppTheme.searchOutline(brightness);
    final label = widget.labelColor ?? AppTheme.secondaryText(brightness);
    final hasCaption = (widget.caption ?? '').trim().isNotEmpty;

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<ChatMediaDownloadState>(
            valueListenable:
                ChatMediaCacheService.instance.watch(widget.voiceUrl),
            builder: (context, state, _) {
              if (state.isDownloaded && state.localPath != null) {
                return _PlayerControls(
                  url: widget.voiceUrl,
                  localPath: state.localPath!,
                  resumeFromMs: _resumeFromMs,
                  knownDurationMs: _knownDurationMs,
                  iconColor: icon,
                  accentColor: accent,
                  trackColor: track,
                  labelColor: label,
                  fmt: _fmt,
                );
              }
              return _DownloadRow(
                state: state,
                knownDurationMs: _knownDurationMs,
                iconColor: icon,
                labelColor: label,
                fmt: _fmt,
                onDownload: () => _download(context),
                onCancel: () => ChatMediaCacheService.instance
                    .cancelDownload(widget.voiceUrl),
              );
            },
          ),
          if (hasCaption) ...[
            const SizedBox(height: 6),
            Text(
              widget.caption!.trim(),
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w700,
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.state,
    required this.knownDurationMs,
    required this.iconColor,
    required this.labelColor,
    required this.fmt,
    required this.onDownload,
    required this.onCancel,
  });

  final ChatMediaDownloadState state;
  final int? knownDurationMs;
  final Color iconColor;
  final Color labelColor;
  final String Function(Duration) fmt;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final durationLabel = (knownDurationMs ?? 0) > 0
        ? fmt(Duration(milliseconds: knownDurationMs!))
        : null;

    Widget trailing;
    VoidCallback? onTap;

    switch (state.phase) {
      case ChatMediaPhase.downloading:
        trailing = SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: state.progress > 0 ? state.progress : null,
            color: iconColor,
          ),
        );
        onTap = onCancel;
        break;
      case ChatMediaPhase.failed:
        trailing = Icon(Icons.refresh_rounded, color: iconColor, size: 26);
        onTap = onDownload;
        break;
      case ChatMediaPhase.notDownloaded:
      case ChatMediaPhase.downloaded:
        trailing = Icon(Icons.download_rounded, color: iconColor, size: 26);
        onTap = onDownload;
        break;
    }

    return Row(
      children: [
        Icon(Icons.mic_rounded, color: iconColor, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            state.isFailed
                ? (state.errorMessage ?? 'Download failed')
                : (durationLabel ?? 'Voice message'),
            style: TextStyle(
              color: labelColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        Tooltip(
          message: state.isDownloading
              ? 'Cancel download'
              : (state.isFailed ? 'Retry download' : 'Download voice message'),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: trailing,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.url,
    required this.localPath,
    required this.resumeFromMs,
    required this.knownDurationMs,
    required this.iconColor,
    required this.accentColor,
    required this.trackColor,
    required this.labelColor,
    required this.fmt,
  });

  final String url;
  final String localPath;
  final int resumeFromMs;
  final int? knownDurationMs;
  final Color iconColor;
  final Color accentColor;
  final Color trackColor;
  final Color labelColor;
  final String Function(Duration) fmt;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ChatAudioPlaybackController.instance,
      builder: (context, _) {
        final controller = ChatAudioPlaybackController.instance;
        final active = controller.isActive(url);
        final playing = controller.isPlaying(url);

        final position = active ? controller.position : Duration(milliseconds: resumeFromMs);
        final totalMs = active && controller.duration.inMilliseconds > 0
            ? controller.duration.inMilliseconds
            : (knownDurationMs ?? 0);
        final duration = Duration(milliseconds: totalMs);

        final progress = totalMs > 0
            ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;

        final atEnd = active &&
            duration > Duration.zero &&
            (duration - position) <= const Duration(milliseconds: 250);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => controller.toggle(
                url: url,
                localPath: localPath,
                resumeFromMs: resumeFromMs,
              ),
              child: Icon(
                playing
                    ? Icons.pause_circle
                    : (atEnd ? Icons.replay_circle_filled : Icons.play_circle),
                size: 34,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: accentColor,
                      inactiveTrackColor: trackColor,
                      thumbColor: accentColor,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: totalMs > 0
                          ? (v) {
                              final target = Duration(
                                milliseconds: (v * totalMs).round(),
                              );
                              if (active) {
                                controller.seekTo(target);
                              } else {
                                controller.playLocalFile(
                                  url: url,
                                  localPath: localPath,
                                  resumeFromMs: target.inMilliseconds,
                                );
                              }
                            }
                          : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          fmt(position),
                          style: TextStyle(
                            fontSize: 11,
                            color: labelColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: active
                                  ? () => controller
                                      .seekBy(const Duration(seconds: -10))
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(Icons.replay_10_rounded,
                                    size: 16,
                                    color: active
                                        ? labelColor
                                        : labelColor.withOpacity(0.35)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: active
                                  ? () => controller.replay()
                                  : () => controller.playLocalFile(
                                        url: url,
                                        localPath: localPath,
                                        resumeFromMs: 0,
                                      ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(Icons.replay_rounded,
                                    size: 16, color: labelColor),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: active
                                  ? () => controller
                                      .seekBy(const Duration(seconds: 10))
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(Icons.forward_10_rounded,
                                    size: 16,
                                    color: active
                                        ? labelColor
                                        : labelColor.withOpacity(0.35)),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          fmt(duration),
                          style: TextStyle(
                            fontSize: 11,
                            color: labelColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
