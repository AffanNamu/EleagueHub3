import 'package:flutter/material.dart';

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

    // Reply (optional)
    this.replySenderName,
    this.replyPreview,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool codeMode;
  final VoidCallback onToggleCodeMode;
  final VoidCallback onPickImage;
  final VoidCallback onSend;
  final bool enabled;

  // Reply context (WhatsApp-style)
  final String? replySenderName;
  final String? replyPreview;
  final VoidCallback? onCancelReply;

  bool get _hasReply =>
      (replySenderName ?? '').trim().isNotEmpty || (replyPreview ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(0.04),
          border: Border(
            top: BorderSide(color: cs.onSurface.withOpacity(0.10)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasReply)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 42,
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
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Cancel reply',
                      onPressed: onCancelReply,
                      icon: Icon(Icons.close_rounded, color: cs.onSurface.withOpacity(0.65)),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Image',
                  onPressed: (!enabled || isSending) ? null : onPickImage,
                  icon: Icon(Icons.image_outlined, color: cs.primary),
                ),
                IconButton(
                  tooltip: codeMode ? 'Code mode: ON' : 'Code mode: OFF',
                  onPressed: (!enabled || isSending) ? null : onToggleCodeMode,
                  icon: Icon(
                    Icons.code,
                    color: codeMode ? cs.primary : cs.onSurface.withOpacity(0.55),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !isSending,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: codeMode ? 'Paste code…' : 'Message…',
                      filled: true,
                      fillColor: cs.onSurface.withOpacity(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.onSurface.withOpacity(0.12)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.onSurface.withOpacity(0.12)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.primary.withOpacity(0.55)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  width: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: (!enabled || isSending) ? null : onSend,
                    child: isSending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
