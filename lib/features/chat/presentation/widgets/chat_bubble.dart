import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.canDelete = false,
    this.onDelete,
    this.onPlayVoice,
    this.isVoicePlaying = false,
    this.voiceProgress = 0.0, // 0..1
    this.voicePositionLabel = '',
    this.voiceDurationLabel = '',
  });

  final ChatMessage message;
  final bool isMe;
  final bool canDelete;
  final VoidCallback? onDelete;

  // Voice playback (controlled by parent screen to avoid multiple players)
  final VoidCallback? onPlayVoice;
  final bool isVoicePlaying;
  final double voiceProgress;
  final String voicePositionLabel;
  final String voiceDurationLabel;

  bool get _hasText => message.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bg = isMe ? cs.primary.withOpacity(0.20) : cs.onSurface.withOpacity(0.06);
    final border = isMe ? cs.primary.withOpacity(0.30) : cs.onSurface.withOpacity(0.12);

    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    final time = message.createdAt?.toDate();
    final timeStr = time == null ? '' : DateFormat('HH:mm').format(time);

    final senderName =
        message.senderName.trim().isEmpty ? 'Player' : message.senderName.trim();
    final senderPhoto = message.senderPhoto.trim();

    Widget content;
    switch (message.type) {
      case ChatMessageType.image:
        content = _ImageBubble(
          url: message.imageUrl,
          caption: _hasText ? message.text : null,
          maxWidth: maxWidth,
        );
        break;
      case ChatMessageType.code:
        content = _CodeBubble(code: message.text, maxWidth: maxWidth);
        break;
      case ChatMessageType.voice:
        content = _VoiceBubble(
          maxWidth: maxWidth,
          caption: _hasText ? message.text : null,
          onPlayPause: onPlayVoice,
          isPlaying: isVoicePlaying,
          progress: voiceProgress,
          positionLabel: voicePositionLabel,
          durationLabel: voiceDurationLabel,
        );
        break;
      case ChatMessageType.text:
      default:
        content = _TextBubble(text: message.text, maxWidth: maxWidth);
        break;
    }

    return Align(
      alignment:
          isMe ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (senderPhoto.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: cs.onSurface.withOpacity(0.08),
                          backgroundImage: NetworkImage(senderPhoto),
                          onBackgroundImageError: (_, __) {},
                        ),
                      ),
                    Flexible(
                      child: Text(
                        senderName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              content,
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.45),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.done_all, size: 14, color: cs.primary.withOpacity(0.65)),
                  ],
                  if (canDelete && onDelete != null) ...[
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: onDelete,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: cs.error.withOpacity(0.70),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.text, required this.maxWidth});
  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.w700,
        height: 1.35,
        fontSize: 13,
      ),
    );
  }
}

class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({
    required this.maxWidth,
    required this.onPlayPause,
    required this.isPlaying,
    required this.progress,
    required this.positionLabel,
    required this.durationLabel,
    this.caption,
  });

  final double maxWidth;
  final VoidCallback? onPlayPause;
  final bool isPlaying;
  final double progress; // 0..1
  final String positionLabel;
  final String durationLabel;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final safeProgress = progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onPlayPause,
              icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle),
              iconSize: 34,
              color: cs.primary,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: safeProgress,
                      minHeight: 5,
                      backgroundColor: cs.onSurface.withOpacity(0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        positionLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        durationLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (caption != null && caption!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption!.trim(),
            style: TextStyle(
              color: cs.onSurface,
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

class _CodeBubble extends StatelessWidget {
  const _CodeBubble({required this.code, required this.maxWidth});
  final String code;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.95),
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              icon: Icon(Icons.copy, size: 16, color: cs.primary),
              label: Text(
                'Copy',
                style: TextStyle(
                    color: cs.primary, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  const _ImageBubble({
    required this.url,
    required this.maxWidth,
    this.caption,
  });

  final String url;
  final String? caption;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    minScale: 0.6,
                    maxScale: 4,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: cs.onSurface.withOpacity(0.06),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: cs.onSurface.withOpacity(0.55)),
                  ),
                  loadingBuilder: (context, child, ev) {
                    if (ev == null) return child;
                    return Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (caption != null && caption!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption!.trim(),
            style: TextStyle(
              color: cs.onSurface,
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
