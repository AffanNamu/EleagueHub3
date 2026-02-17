import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  final ChatMessage message;
  final bool isMe;

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

    final senderName = message.senderName.trim().isEmpty ? 'Player' : message.senderName.trim();

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
      case ChatMessageType.text:
      default:
        content = _TextBubble(text: message.text, maxWidth: maxWidth);
        break;
    }

    return Align(
      alignment: isMe ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
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
                Text(
                  senderName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
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
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900, fontSize: 12),
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
                    child: Icon(Icons.broken_image_outlined, color: cs.onSurface.withOpacity(0.55)),
                  ),
                  loadingBuilder: (context, child, ev) {
                    if (ev == null) return child;
                    return Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
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
