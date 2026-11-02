import 'package:flutter/material.dart';

import '../../../../core/locale/app_localizations.dart';
import '../../../../core/widgets/glass.dart';
import 'voice_record_controls.dart';

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

    // Voice (optional) — Telegram-style press-and-hold on the trailing
    // button: press starts recording, release PAUSES it (never
    // auto-sends -- see VoiceRecordButton.onRecordPause), slide left
    // cancels, slide up locks into hands-free active recording. All four
    // are required together (a screen either offers voice or it doesn't).
    this.onRecordStart,
    this.onRecordCancel,
    this.onRecordPause,
    this.onRecordLock,
    this.onRecordDragUpdate,
    this.onRecordQuickTap,
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

  // Voice action (optional) -- see VoiceRecordButton for the gesture contract.
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordCancel;
  final VoidCallback? onRecordPause;
  final VoidCallback? onRecordLock;
  final ValueChanged<VoiceRecordDrag>? onRecordDragUpdate;

  /// Fires on a quick tap (released before the long-press deadline, so
  /// no recording ever started) -- lets the screen show a "hold to
  /// record" hint instead of the tap doing nothing visible at all.
  final VoidCallback? onRecordQuickTap;
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
        final canRecord = enabled &&
            !isSending &&
            onRecordStart != null &&
            onRecordCancel != null &&
            onRecordPause != null &&
            onRecordLock != null;

        final trailingIsSend = hasText;
        final trailingEnabled = trailingIsSend ? canSend : canRecord;

        final trailingBg = trailingEnabled ? cs.primary : cs.onSurface.withOpacity(0.14);
        final trailingFg = trailingEnabled ? cs.onPrimary : cs.onSurface.withOpacity(0.45);

        final hint = codeMode
            ? context.l10n.tr('chat_input_paste_code_hint')
            : context.l10n.tr('chat_input_message_hint');

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
                                "${context.l10n.tr('chat_input_replying_to_prefix')}${((replySenderName ?? '').trim().isEmpty ? context.l10n.tr('chat_input_reply_fallback_name') : replySenderName!.trim())}",
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
                          tooltip: context.l10n.tr('chat_input_cancel_reply_tooltip'),
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
                              tooltip: context.l10n.tr('chat_input_image_tooltip'),
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
                    if (trailingIsSend)
                      Tooltip(
                        message: context.l10n.tr('chat_input_send_tooltip'),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: trailingEnabled ? onSend : null,
                            borderRadius: BorderRadius.circular(999),
                            child: Ink(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: trailingBg,
                              ),
                              child: Center(
                                child: isSending
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: trailingFg,
                                        ),
                                      )
                                    : Icon(
                                        Icons.send_rounded,
                                        size: 20,
                                        color: trailingFg,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Tooltip(
                        message: (voiceTooltip ?? '').trim().isNotEmpty
                            ? voiceTooltip!.trim()
                            : context.l10n.tr('chat_input_record_voice_tooltip'),
                        // Tooltip defaults to TooltipTriggerMode.longPress,
                        // which installs its own competing long-press
                        // recognizer on this child, alongside
                        // VoiceRecordButton's own below. In practice the
                        // child's recognizer wins that race (confirmed
                        // against the recognizer/arena source), so this
                        // wasn't the cause of recordings failing to start --
                        // but it's a real, known Flutter footgun regardless,
                        // so forcing tap mode here removes it on general
                        // principle: a quick tap now shows the tooltip
                        // bubble instead of competing for the long-press at
                        // all, and holding still starts recording exactly
                        // as before.
                        //
                        // Press and hold to record (Telegram-style) -- see
                        // VoiceRecordButton for the full gesture contract
                        // (release pauses -- never auto-sends, see
                        // onRecordPause -- slide left to cancel, slide up
                        // to lock hands-free). A plain tap/quick-release
                        // never starts a recording by design, same as
                        // Telegram -- but it's not silent: see onQuickTap.
                        triggerMode: TooltipTriggerMode.tap,
                        child: VoiceRecordButton(
                          enabled: trailingEnabled,
                          onRecordStart: onRecordStart ?? () {},
                          onRecordCancel: onRecordCancel ?? () {},
                          onRecordPause: onRecordPause ?? () {},
                          onRecordLock: onRecordLock ?? () {},
                          onDragUpdate: onRecordDragUpdate,
                          onQuickTap: onRecordQuickTap,
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
