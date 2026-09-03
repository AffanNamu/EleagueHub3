import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/chat_message.dart';
import 'chat_image_media.dart';
import 'voice_message_player.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onSwipeReply,
  });

  final ChatMessage message;
  final bool isMe;

  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final VoidCallback? onSwipeReply;

  bool get _hasText => message.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final baseBg = isMe
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccentDark.withOpacity(0.16)
            : const Color(0xFFECFCCB))
        : AppTheme.searchBackground(brightness);
    final baseBorder = isMe
        ? AppTheme.limeAccentDark.withOpacity(0.30)
        : AppTheme.searchOutline(brightness);

    final bg = selected
        ? (brightness == Brightness.dark
            ? AppTheme.limeAccent.withOpacity(0.18)
            : const Color(0xFFD9F99D))
        : baseBg;
    final border = selected
        ? AppTheme.limeAccentDark.withOpacity(0.65)
        : baseBorder;

    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    final time = message.createdAt?.toDate();
    final timeStr = time == null ? '' : DateFormat('HH:mm').format(time);

    final senderName = message.displaySenderName;
    final senderPhoto = message.senderPhoto.trim();

    Widget content;
    if (message.deleted) {
      content = Text(
        'This message was deleted',
        style: TextStyle(
          color: AppTheme.secondaryText(brightness),
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          height: 1.35,
          fontSize: 13,
        ),
      );
    } else {
      switch (message.type) {
        case ChatMessageType.image:
          content = ChatImageMedia(
            imageUrl: message.imageUrl,
            caption: _hasText ? message.text : null,
            maxWidth: maxWidth,
          );
          break;
        case ChatMessageType.code:
          content = _CodeBubble(code: message.text, maxWidth: maxWidth);
          break;
        case ChatMessageType.voice:
          content = VoiceMessagePlayer(
            voiceUrl: message.voiceUrl,
            durationMsHint: message.voiceDurationMs,
            width: maxWidth < 260 ? maxWidth : 260.0,
            caption: _hasText ? message.text : null,
          );
          break;
        case ChatMessageType.text:
        default:
          content = _TextBubble(text: message.text, maxWidth: maxWidth);
          break;
      }
    }

    final bubble = Align(
      alignment: isMe
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
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
                            backgroundColor:
                                AppTheme.iconCircleBackground(brightness),
                            backgroundImage: NetworkImage(senderPhoto),
                            onBackgroundImageError: (_, __) {},
                          ),
                        ),
                      Flexible(
                        child: Text(
                          senderName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondaryText(brightness),
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
                if (message.isReply)
                  _ReplyQuote(
                    senderName: message.replyToSenderName.trim().isEmpty
                        ? 'Message'
                        : message.replyToSenderName.trim(),
                    preview: message.replyToText.trim().isEmpty
                        ? 'Message'
                        : message.replyToText.trim(),
                  ),
                content,
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.done_all,
                        size: 14,
                        color: AppTheme.limeAccentDark.withOpacity(0.8),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onSwipeReply == null) return bubble;

    return Dismissible(
      key: ValueKey<String>('reply-swipe-${message.messageId}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        HapticFeedback.selectionClick();
        onSwipeReply?.call();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: AppTheme.limeAccent.withOpacity(0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.reply_rounded,
          color: AppTheme.limeAccentDark,
        ),
      ),
      child: bubble,
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.senderName,
    required this.preview,
  });

  final String senderName;
  final String preview;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.limeAccentDark,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.limeAccentDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.secondaryText(
                      Theme.of(context).brightness,
                    ),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final brightness = Theme.of(context).brightness;
    return Text(
      text,
      style: TextStyle(
        color: AppTheme.primaryText(brightness),
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
    final brightness = Theme.of(context).brightness;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppTheme.primaryText(brightness),
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
              icon: const Icon(
                Icons.copy,
                size: 16,
                color: AppTheme.limeAccentDark,
              ),
              label: const Text(
                'Copy',
                style: TextStyle(
                  color: AppTheme.limeAccentDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
