import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../live/logic/quick_messages_controller.dart';
import '../../live/presentation/widgets/live_floating_quick_message.dart';
import '../logic/call_session_controller.dart';

String _trOr(AppLocalizations l10n, String key, String fallback) {
  final v = l10n.tr(key);
  return v == key ? fallback : v;
}

class CallRoomScreen extends ConsumerStatefulWidget {
  const CallRoomScreen({super.key});

  @override
  ConsumerState<CallRoomScreen> createState() => _CallRoomScreenState();
}

class _CallRoomScreenState extends ConsumerState<CallRoomScreen> {
  final TextEditingController _codeCtrl = TextEditingController();
  Timer? _incomingHideTimer;

  @override
  void dispose() {
    _incomingHideTimer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Premium, theme-consistent semantic accents (soft, not neon).
    const success = Color(0xFF22C55E);
    const warning = Color(0xFFF59E0B);

    final st = ref.watch(callSessionControllerProvider);
    final ctrl = ref.read(callSessionControllerProvider.notifier);

    if (st.incomingQuickText != null) {
      _incomingHideTimer?.cancel();
      _incomingHideTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {});
      });
    }

    final quickList = ref.watch(overlayQuickMessagesProvider);

    final showIncoming = st.incomingQuickText != null &&
        (DateTime.now().millisecondsSinceEpoch - st.incomingQuickAtMs) < 3200;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(_trOr(l10n, 'call_room_title', 'Voice Room')),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _trOr(
                          l10n,
                          'call_room_how_title',
                          'Create or join with 8-digit code',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _trOr(
                          l10n,
                          'call_room_how_body',
                          'Create a room to get an 8-digit code. Share it with your friend to join. Keep talking using the floating overlay over other apps.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (st.error.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: st.reconnecting
                                ? warning.withOpacity(0.12)
                                : cs.error.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: st.reconnecting
                                  ? warning.withOpacity(0.30)
                                  : cs.error.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (st.reconnecting) ...[
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: warning,
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ] else ...[
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: cs.error,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  st.error,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: st.reconnecting ? warning : cs.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (st.joining || st.reconnecting)
                                  ? null
                                  : () async => ctrl.createAndJoin(),
                              icon: st.joining
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.add_call),
                              label: Text(
                                _trOr(l10n, 'call_room_create', 'Create'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (!st.connected &&
                                      !st.joining &&
                                      !st.reconnecting)
                                  ? () async {
                                      final code = _codeCtrl.text.trim();
                                      await ctrl.joinByCode(code);
                                    }
                                  : null,
                              icon: const Icon(Icons.login),
                              label: Text(
                                _trOr(l10n, 'call_room_join', 'Join'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _codeCtrl,
                        enabled:
                            !st.connected && !st.joining && !st.reconnecting,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: _trOr(
                            l10n,
                            'call_room_code_hint',
                            'Enter 8-digit code',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _trOr(l10n, 'call_room_status_title', 'Status'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: st.connected
                                  ? success
                                  : st.reconnecting
                                      ? warning
                                      : cs.onSurface.withOpacity(0.30),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              st.connected
                                  ? '${_trOr(l10n, 'call_room_connected', 'Connected')} • ${_trOr(l10n, 'call_room_code', 'Code')}: ${st.callId}'
                                  : st.reconnecting
                                      ? _trOr(l10n, 'call_room_reconnecting',
                                          'Reconnecting...')
                                      : _trOr(l10n, 'call_room_not_connected',
                                          'Not connected'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: st.connected
                                    ? success
                                    : st.reconnecting
                                        ? warning
                                        : cs.onSurface.withOpacity(0.75),
                              ),
                            ),
                          ),
                          if (st.connected)
                            IconButton(
                              tooltip: _trOr(l10n, 'common_copy', 'Copy'),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: st.callId),
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                      _trOr(l10n, 'call_room_copied',
                                          'Code copied'),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (st.connected || st.reconnecting)
                                  ? ctrl.leave
                                  : null,
                              icon: const Icon(Icons.call_end),
                              label: Text(
                                _trOr(l10n, 'call_room_leave', 'Leave'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (st.connected &&
                                      st.micPermissionGranted)
                                  ? ctrl.toggleMic
                                  : null,
                              icon: Icon(
                                st.micEnabled ? Icons.mic : Icons.mic_off,
                              ),
                              label: Text(
                                st.micEnabled
                                    ? _trOr(l10n, 'call_room_mic_on', 'Mic on')
                                    : _trOr(l10n, 'call_room_mic_off',
                                        'Mic off'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        st.micPermissionGranted
                            ? _trOr(l10n, 'call_room_mic_hint_ok',
                                'Mic permission granted')
                            : _trOr(
                                l10n,
                                'call_room_mic_hint_denied',
                                'Mic permission denied (you can still listen)',
                              ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (showIncoming)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: IgnorePointer(
                  ignoring: true,
                  child: Glass(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt, color: cs.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            st.incomingQuickFrom == null
                                ? st.incomingQuickText!
                                : '${st.incomingQuickFrom}: ${st.incomingQuickText!}',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            LiveFloatingQuickMessage(
              enabled: st.connected,
              messages: quickList,
              onSend: (m) => ref
                  .read(callSessionControllerProvider.notifier)
                  .sendQuick(m),
              icon: Icons.message_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
