import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

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
  bool _requestingPermissions = false;

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

  // ── REQUEST MIC & CAMERA PERMISSIONS BEFORE CALL ─────────────────────────
  Future<bool> _requestCallPermissions() async {
    if (_requestingPermissions) return false;

    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    // Show dialog explaining why permissions are needed
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(brightness),
        surfaceTintColor: Colors.transparent,
        icon: Icon(Icons.mic, color: AppTheme.limeAccent, size: 48),
        title: Text(
          _trOr(
            l10n,
            'call_permission_title',
            'Microphone & Camera Access',
          ),
        ),
        content: Text(
          _trOr(
            l10n,
            'call_permission_body',
            'To create or join a voice room, the app needs access to your microphone. Camera access is optional for video features.\n\nYou can change this anytime in Android Settings.',
          ),
          style: TextStyle(
            height: 1.5,
            color: AppTheme.primaryText(brightness),
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
            child: Text(_trOr(l10n, 'common_allow', 'Allow')),
          ),
        ],
      ),
    );

    if (proceed != true) return false;

    setState(() => _requestingPermissions = true);

    try {
      // Request microphone permission
      final micStatus = await Permission.microphone.request();
      final micGranted = micStatus.isGranted;

      // Request camera permission (optional for voice, but good to have)
      final cameraStatus = await Permission.camera.request();
      final cameraGranted = cameraStatus.isGranted;

      if (!mounted) return false;

      if (!micGranted) {
        // Mic permission denied — show helpful message
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.cardColor(brightness),
            surfaceTintColor: Colors.transparent,
            icon: Icon(Icons.warning_amber, color: Colors.orange, size: 48),
            title: Text(
              _trOr(
                l10n,
                'call_permission_denied_title',
                'Microphone Access Denied',
              ),
            ),
            content: Text(
              _trOr(
                l10n,
                'call_permission_denied_body',
                'Microphone access is required to create or join voice rooms. You can enable it in Android Settings.',
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
                child: Text(_trOr(l10n, 'common_open_settings', 'Open Settings')),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await openAppSettings();
        }

        setState(() => _requestingPermissions = false);
        return false;
      }

      setState(() => _requestingPermissions = false);
      return true;
    } catch (e) {
      setState(() => _requestingPermissions = false);
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Permission request failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<void> _handleCreateRoom() async {
    final ctrl = ref.read(callSessionControllerProvider.notifier);
    final st = ref.read(callSessionControllerProvider);

    if (st.joining || st.reconnecting || st.connected) return;

    // Request permissions BEFORE creating room
    final granted = await _requestCallPermissions();
    if (!granted || !mounted) return;

    await ctrl.createAndJoin();
  }

  Future<void> _handleJoinRoom() async {
    final ctrl = ref.read(callSessionControllerProvider.notifier);
    final st = ref.read(callSessionControllerProvider);
    final code = _codeCtrl.text.trim().toUpperCase();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Please enter a room code'),
        ),
      );
      return;
    }

    if (st.joining || st.reconnecting || st.connected) return;

    // Request permissions BEFORE joining room
    final granted = await _requestCallPermissions();
    if (!granted || !mounted) return;

    await ctrl.joinByCode(code);
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
          // ── Overlay Toggle Button (Top-Right) ───────────────────────────
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
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Permission Status Banner ───────────────────────────────
                if (!st.micPermissionGranted)
                  Glass(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(12),
                    fill: warning.withOpacity(0.10),
                    borderColor: warning.withOpacity(0.30),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: warning, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _trOr(
                              l10n,
                              'call_room_mic_not_granted',
                              'Microphone permission not granted. Tap Create or Join to request access.',
                            ),
                            style: TextStyle(
                              color: warning,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (st.micPermissionGranted)
                  Glass(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(12),
                    fill: success.withOpacity(0.10),
                    borderColor: success.withOpacity(0.30),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _trOr(
                              l10n,
                              'call_room_mic_granted',
                              'Microphone access granted. Ready to call.',
                            ),
                            style: TextStyle(
                              color: success,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                // ── Create / Join Card ─────────────────────────────────────
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
                              onPressed: (st.joining ||
                                      st.reconnecting ||
                                      _requestingPermissions)
                                  ? null
                                  : _handleCreateRoom,
                              icon: st.joining || _requestingPermissions
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
                                      !st.reconnecting &&
                                      !_requestingPermissions)
                                  ? _handleJoinRoom
                                  : null,
                              icon: st.joining || _requestingPermissions
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login),
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
                        enabled: !st.connected &&
                            !st.joining &&
                            !st.reconnecting &&
                            !_requestingPermissions,
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

                // ── Status Card ────────────────────────────────────────────
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
                              onPressed: (st.connected && st.micPermissionGranted)
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
