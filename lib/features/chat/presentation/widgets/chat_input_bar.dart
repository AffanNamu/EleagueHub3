import 'package:flutter/material.dart';

import '../../../../core/widgets/glass.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.isSending,
    required this.codeMode,
    required this.onToggleCodeMode,
    required this.onPickImage,
    required this.onSend,
    required this.enabled,

    // Voice (optional) — merged WhatsApp-style into trailing button
    this.onRecordVoice,
    this.voiceTooltip,

    // Reply (optional)
    this.replySenderName,
    this.replyPreview,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final bool isSending;

  /// Kept for backwards compatibility (sending logic may still use it).
  /// UI toggle is intentionally removed.
  final bool codeMode;

  /// Kept for backwards compatibility (UI toggle removed).
  final VoidCallback onToggleCodeMode;

  final VoidCallback onPickImage;
  final VoidCallback onSend;
  final bool enabled;

  // Voice action (optional)
  final VoidCallback? onRecordVoice;
  final String? voiceTooltip;

  // Reply context (WhatsApp-style)
  final String? replySenderName;
  final String? replyPreview;
  final VoidCallback? onCancelReply;

  bool get _hasReply =>
      (replySenderName ?? '').trim().isNotEmpty || (replyPreview ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final text = controller.text.trim();
        final hasText = text.isNotEmpty;

        final canSend = enabled && !isSending;
        final canRecord = enabled && !isSending && onRecordVoice != null;

        final trailingIsSend = hasText;
        final trailingEnabled = trailingIsSend ? canSend : canRecord;

        final trailingBg = trailingEnabled ? cs.primary : cs.onSurface.withOpacity(0.14);
        final trailingFg = trailingEnabled ? cs.onPrimary : cs.onSurface.withOpacity(0.45);

        final hint = codeMode ? 'Paste code…' : 'Message…';

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasReply)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Replying to ${((replySenderName ?? '').trim().isEmpty ? 'message' : replySenderName!.trim())}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (replyPreview ?? '').trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.75),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Cancel reply',
                          onPressed: onCancelReply,
                          icon: Icon(Icons.close_rounded, color: cs.onSurface.withOpacity(0.65)),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Glass(
                        borderRadius: 999,
                        padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Image',
                              onPressed: (!enabled || isSending) ? null : onPickImage,
                              icon: Icon(Icons.image_outlined, color: cs.primary),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 40),
                                child: TextField(
                                  controller: controller,
                                  enabled: enabled && !isSending,
                                  maxLines: 5,
                                  minLines: 1,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => onSend(),
                                  decoration: InputDecoration(
                                    hintText: hint,
                                    hintStyle: TextStyle(
                                      color: cs.onSurface.withOpacity(0.55),
                                      fontWeight: FontWeight.w700,
                                    ),
                                    isDense: true,
                                    filled: false,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: trailingIsSend
                          ? 'Send'
                          : ((voiceTooltip ?? '').trim().isNotEmpty ? voiceTooltip!.trim() : 'Record voice'),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: trailingEnabled ? (trailingIsSend ? onSend : onRecordVoice) : null,
                          borderRadius: BorderRadius.circular(999),
                          child: Ink(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: trailingBg,
                            ),
                            child: Center(
                              child: isSending && trailingIsSend
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: trailingFg,
                                      ),
                                    )
                                  : Icon(
                                      trailingIsSend ? Icons.send_rounded : Icons.mic,
                                      size: 20,
                                      color: trailingFg,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
