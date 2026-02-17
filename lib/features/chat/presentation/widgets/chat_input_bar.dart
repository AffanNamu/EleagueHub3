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
  });

  final TextEditingController controller;
  final bool isSending;
  final bool codeMode;
  final VoidCallback onToggleCodeMode;
  final VoidCallback onPickImage;
  final VoidCallback onSend;
  final bool enabled;

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
        child: Row(
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
      ),
    );
  }
}
