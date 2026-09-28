// lib/features/highlights/presentation/highlight_player_screen.dart
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/locale/app_localizations.dart';

/// Full-screen in-app player for a highlight clip's Cloudinary secureUrl.
///
/// Replaces the previous "open externally" behavior -- the clip is already
/// compressed down to a small, network-friendly size (see
/// VideoCompressionService's policy), so a plain progressive-download
/// player with normal buffering plays smoothly without needing HLS/
/// adaptive streaming.
class HighlightPlayerScreen extends StatefulWidget {
  const HighlightPlayerScreen({super.key, required this.videoUrl, this.title});

  final String videoUrl;
  final String? title;

  @override
  State<HighlightPlayerScreen> createState() => _HighlightPlayerScreenState();
}

class _HighlightPlayerScreenState extends State<HighlightPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    _chewieController?.dispose();
    _chewieController = null;
    await _videoController?.dispose();
    _videoController = null;

    final uri = Uri.tryParse(widget.videoUrl.trim());
    if (uri == null) {
      setState(() {
        _loading = false;
        _error = StateError('Invalid video URL');
      });
      return;
    }

    try {
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _videoController = controller;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: true,
      );

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          (widget.title ?? '').trim().isNotEmpty ? widget.title!.trim() : '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Colors.white)
            : _error != null
                ? _ErrorState(message: l10n.tr('league_highlights_open_video_failed'), onRetry: _init)
                : _chewieController != null
                    ? AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio == 0
                            ? 16 / 9
                            : _videoController!.value.aspectRatio,
                        child: Chewie(controller: _chewieController!),
                      )
                    : _ErrorState(message: l10n.tr('league_highlights_open_video_failed'), onRetry: _init),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.white70, size: 36),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
          child: Text(l10n.tr('common_retry')),
        ),
      ],
    );
  }
}

/// Opens [HighlightPlayerScreen] as a full-screen route.
Future<void> openHighlightPlayer(BuildContext context, {required String videoUrl, String? title}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HighlightPlayerScreen(videoUrl: videoUrl, title: title),
      fullscreenDialog: true,
    ),
  );
}
