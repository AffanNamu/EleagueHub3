import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/platform/overlay_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../live/logic/quick_messages_controller.dart';
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

  bool _overlayEnabled = false;
  bool _overlayGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadOverlayState());
    });
  }

  @override
  void dispose() {
    _incomingHideTimer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOverlayState() async {
    try {
      final prefs = ref.read(prefsServiceProvider);
      final enabled = prefs.liveOverlayEnabled();
      final granted = await OverlayPlatform.isOverlayPermissionGranted();
      if (!mounted) return;
      setState(() {
        _overlayEnabled = enabled;
        _overlayGranted = granted;
      });
    } catch (_) {}
  }

  Future<void> _toggleOverlay() async {
    final prefs = ref.read(prefsServiceProvider);
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    if (_overlayEnabled) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardColor(brightness),
          surfaceTintColor: Colors.transparent,
          title: Text(
            _trOr(l10n, 'live_overlay_turn_off_title', 'Turn off overlay?'),
          ),
          content: Text(
            _trOr(
              l10n,
              'live_overlay_turn_off_body',
              'This will hide the floating voice/message controls.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_trOr(l10n, 'common_cancel', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_trOr(l10n, 'common_turn_off', 'Turn off')),
            ),
          ],
        ),
      );

      if (sure != true) return;

      await prefs.setLiveOverlayEnabled(false);
      await OverlayPlatform.stopGlobalOverlay();

      if (!mounted) return;
      setState(() {
        _overlayEnabled = false;
      });
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(brightness),
        surfaceTintColor: Colors.transparent,
        title: Text(
          _trOr(l10n, 'live_overlay_enable_title', 'Enable floating overlay?'),
        ),
        content: Text(
          _trOr(
            l10n,
            'live_overlay_enable_body',
            'This shows a floating voice/message control above other apps. Android will ask for "Appear on top" permission.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_trOr(l10n, 'common_cancel', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_trOr(l10n, 'common_continue', 'Continue')),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    await prefs.setLiveOverlayEnabled(true);

    final granted = await OverlayPlatform.isOverlayPermissionGranted();
    if (!mounted) return;

    setState(() {
      _overlayEnabled = true;
      _overlayGranted = granted;
    });

    if (granted) {
      await OverlayPlatform.startGlobalOverlay();
      return;
    }

    await OverlayPlatform.requestOverlayPermission();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _trOr(
            l10n,
            'live_overlay_permission_snackbar',
            'Grant the overlay permission, then return to the app.',
          ),
        ),
      ),
    );

    await _loadOverlayState();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    const success = Color(0xFF22C55E);
    const warning = Color(0xFFF59E0B);

    final st = ref.watch(callSessionControllerProvider);
    final ctrl = ref.read(callSessionControllerProvider.notifier);

    if (_codeCtrl.text != st.callId && st.callId.isNotEmpty) {
      _codeCtrl.text = st.callId;
      _codeCtrl.selection =
          TextSelection.collapsed(offset: _codeCtrl.text.length);
    }

    if (st.incomingQuickText != null) {
      _incomingHideTimer?.cancel();
      _incomingHideTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {});
      });
    }

    final quickList = ref.watch(overlayQuickMessagesProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(OverlayPlatform.setOverlayQuickMessages(quickList));
    });

    final showIncoming = st.incomingQuickText != null &&
        (DateTime.now().millisecondsSinceEpoch - st.incomingQuickAtMs) < 3200;

    final overlayIcon = !_overlayEnabled
        ? Icons.picture_in_picture_alt_outlined
        : (_overlayGranted
            ? Icons.picture_in_picture_alt
            : Icons.warning_amber_rounded);

    final overlayIconColor = !_overlayEnabled
        ? AppTheme.limeAccentDark
        : (_overlayGranted ? AppTheme.limeAccentDark : warning);

    return GlassScaffold(
      appBar: AppBar(
        title: Text(_trOr(l10n, 'call_room_title', 'Voice Room')),
        actions: [
          IconButton(
            tooltip: _overlayEnabled
                ? (_overlayGranted
                    ? _trOr(
                        l10n,
                        'live_overlay_on_tooltip',
                        'Overlay is ON',
                      )
                    : _trOr(
                        l10n,
                        'live_overlay_permission_needed_tooltip',
                        'Overlay needs permission',
                      ))
                : _trOr(
                    l10n,
                    'live_overlay_off_tooltip',
                    'Overlay is OFF',
                  ),
            onPressed: _toggleOverlay,
            icon: Icon(overlayIcon, color: overlayIconColor),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Glass(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(14),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Create or join with 8-character code',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _overlayEnabled
                            ? 'Create a room to get an 8-character code. Share it with your friend to join. Keep talking using the floating overlay over other apps.'
                            : 'Create a room to get an 8-character code. Share it with your friend to join. Enable the floating overlay from the top-right button for premium quick controls.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
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
                                : Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: st.reconnecting
                                  ? warning.withOpacity(0.30)
                                  : Theme.of(context)
                                      .colorScheme
                                      .error
                                      .withOpacity(0.25),
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
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  st.error,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: st.reconnecting
                                        ? warning
                                        : Theme.of(context).colorScheme.error,
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
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.limeAccent,
                                foregroundColor: AppTheme.darkText,
                              ),
                              onPressed: (st.joining || st.reconnecting)
                                  ? null
                                  : () async => ctrl.createAndJoin(),
                              icon: st.joining
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.darkText,
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
                                      final code =
                                          _codeCtrl.text.trim().toUpperCase();
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
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 8,
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: 'Enter 8-character code',
                        ),
                        onChanged: (v) {
                          final next = v
                              .toUpperCase()
                              .replaceAll(RegExp(r'[^A-Z0-9]'), '');
                          if (next != v) {
                            _codeCtrl.value = TextEditingValue(
                              text: next,
                              selection:
                                  TextSelection.collapsed(offset: next.length),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Glass(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(14),
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _trOr(l10n, 'call_room_status_title', 'Status'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(brightness),
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
                                      : AppTheme.secondaryText(brightness)
                                          .withOpacity(0.40),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              st.connected
                                  ? '${_trOr(l10n, 'call_room_connected', 'Connected')} • Code: ${st.callId}'
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
                                        : AppTheme.secondaryText(brightness),
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
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.limeAccent,
                                foregroundColor: AppTheme.darkText,
                              ),
                              onPressed:
                                  (st.connected && st.micPermissionGranted)
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
                          color: AppTheme.secondaryText(brightness),
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
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt,
                          color: AppTheme.limeAccentDark,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            st.incomingQuickFrom == null
                                ? st.incomingQuickText!
                                : '${st.incomingQuickFrom}: ${st.incomingQuickText!}',
                            style: TextStyle(
                              color: AppTheme.primaryText(brightness),
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
          ],
        ),
      ),
    );
  }
}
