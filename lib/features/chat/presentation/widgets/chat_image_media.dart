//lib/features/chat/presentation/widgets/chat_image_media.dart
//
// WhatsApp-style image bubble:
// - Always shows a small, cheap Cloudinary-transformed thumbnail (never
//   the full-resolution original) so the chat renders instantly.
// - Full image is only fetched when the user taps Download.
// - Once downloaded, the file is cached locally (via ChatMediaCacheService)
//   and tapping opens an offline full-screen viewer from that local file.

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/chat_media_cache_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/cloudinary_media_utils.dart';

class ChatImageMedia extends StatelessWidget {
  const ChatImageMedia({
    super.key,
    required this.imageUrl,
    required this.maxWidth,
    this.caption,
  });

  final String imageUrl;
  final double maxWidth;
  final String? caption;

  bool get _hasCaption => (caption ?? '').trim().isNotEmpty;

  void _openFullScreen(BuildContext context, String localPath) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            minScale: 0.6,
            maxScale: 4,
            child: Image.file(File(localPath), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final thumbUrl = CloudinaryMediaUtils.imageThumbnail(imageUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: AppTheme.searchBackground(brightness),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: ValueListenableBuilder<ChatMediaDownloadState>(
                valueListenable:
                    ChatMediaCacheService.instance.watch(imageUrl),
                builder: (context, state, _) {
                  final downloaded = state.isDownloaded && state.localPath != null;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onTap: downloaded
                            ? () => _openFullScreen(context, state.localPath!)
                            : null,
                        child: downloaded
                            ? Image.file(
                                File(state.localPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _BrokenImage(
                                  brightness: brightness,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: thumbUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _BrokenImage(
                                  brightness: brightness,
                                ),
                                placeholder: (_, __) => const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.limeAccentDark,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (!downloaded)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: _DownloadControl(
                            url: imageUrl,
                            state: state,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (_hasCaption) ...[
          const SizedBox(height: 8),
          Text(
            caption!.trim(),
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w700,
              height: 1.35,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage({required this.brightness});
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: AppTheme.secondaryText(brightness),
      ),
    );
  }
}

class _DownloadControl extends StatelessWidget {
  const _DownloadControl({required this.url, required this.state});

  final String url;
  final ChatMediaDownloadState state;

  Future<void> _download(BuildContext context) async {
    try {
      await ChatMediaCacheService.instance.download(
        url: url,
        kind: ChatMediaKind.image,
      );
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
    Widget icon;
    VoidCallback? onTap;

    switch (state.phase) {
      case ChatMediaPhase.downloading:
        icon = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: state.progress > 0 ? state.progress : null,
            color: Colors.white,
          ),
        );
        onTap = () => ChatMediaCacheService.instance.cancelDownload(url);
        break;
      case ChatMediaPhase.failed:
        icon = const Icon(Icons.refresh_rounded, color: Colors.white, size: 20);
        onTap = () => _download(context);
        break;
      case ChatMediaPhase.notDownloaded:
      case ChatMediaPhase.downloaded:
        icon = const Icon(Icons.download_rounded, color: Colors.white, size: 20);
        onTap = () => _download(context);
        break;
    }

    return Tooltip(
      message: state.isFailed
          ? (state.errorMessage ?? 'Retry download')
          : (state.isDownloading ? 'Cancel download' : 'Download image'),
      child: Material(
        color: Colors.black.withOpacity(0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: icon,
          ),
        ),
      ),
    );
  }
}
