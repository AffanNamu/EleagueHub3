import 'dart:async';
import 'dart:io';

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

/// The default quick messages, localized. Reuses the same translation keys
/// as the in-app quick message picker (see live_view_screen.dart) so the
/// Android overlay (which has no BuildContext of its own) shows the same
/// localized text.
List<String> _localizedDefaultQuickMessages(AppLocalizations l10n) {
  return <String>[
    _trOr(l10n, 'live_view_quick_focus', 'Focus!'),
    _trOr(l10n, 'live_view_quick_calm_down', 'Calm down'),
    _trOr(l10n, 'live_view_quick_we_got_this', 'We got this'),
    _trOr(l10n, 'live_view_quick_one_more_goal', 'One more goal!'),
    _trOr(l10n, 'live_view_quick_dont_give_up', 'Don’t give up'),
    _trOr(l10n, 'live_view_quick_sorry', 'Sorry'),
    _trOr(l10n, 'live_view_quick_unlucky', 'Unlucky'),
    _trOr(l10n, 'live_view_quick_what_a_goal', 'What a goal!'),
    _trOr(l10n, 'live_view_quick_ref', 'Ref??'),
  ];
}

/// Resolves a single semantic error key (see [CallSessionErrorKey]) to
/// localized display text.
String _callErrorKeyToText(AppLocalizations l10n, String key) {
  switch (key) {
    case CallSessionErrorKey.signInRequired:
      return _trOr(l10n, 'call_error_sign_in_required', 'Please sign in to use voice rooms.');
    case CallSessionErrorKey.invalidRoomCode:
      return _trOr(l10n, 'call_error_invalid_room_code', 'Room code must be exactly 8 letters/numbers.');
    case CallSessionErrorKey.networkIssue:
      return _trOr(l10n, 'call_error_network_issue', 'Network issue. Please check your connection.');
    case CallSessionErrorKey.connectionTimeout:
      return _trOr(l10n, 'call_error_connection_timeout', 'Connection timed out. Please try again.');
    case CallSessionErrorKey.permissionDenied:
      return _trOr(l10n, 'call_error_permission_denied', 'Permission denied. Please check app permissions.');
    case CallSessionErrorKey.authFailed:
      return _trOr(l10n, 'call_error_auth_failed', 'Authentication failed. Please sign in again.');
    case CallSessionErrorKey.roomConnectFailed:
      return _trOr(l10n, 'call_error_room_connect_failed', 'Could not connect to voice room. Please try again.');
    case CallSessionErrorKey.reconnectGiveUp:
      return _trOr(l10n, 'call_error_reconnect_give_up', 'Could not reconnect. Please rejoin manually.');
    case CallSessionErrorKey.unknown:
    default:
      return _trOr(l10n, 'call_error_unknown', 'Something went wrong. Please try again.');
  }
}

/// Resolves the full (possibly composite) error text for [state].
String _callErrorText(AppLocalizations l10n, CallSessionState state) {
  final key = state.errorKey;
  final arg = state.errorArg;

  if (key == CallSessionErrorKey.reconnectingWithReason) {
    String reasonText;
    if (arg != null && arg.startsWith('raw|')) {
      reasonText = arg.substring('raw|'.length);
    } else if (arg != null && arg.startsWith('key|')) {
      reasonText = _callErrorKeyToText(l10n, arg.substring('key|'.length));
    } else {
      reasonText = _callErrorKeyToText(l10n, CallSessionErrorKey.unknown);
    }
    return '${_trOr(l10n, 'call_error_reconnecting_prefix', 'Reconnecting... ')}$reasonText';
  }

  if (key == CallSessionErrorKey.connectionLostReconnecting) {
    final parts = (arg ?? '').split('/');
    final attempt = parts.isNotEmpty ? parts[0] : '';
    final max = parts.length > 1 ? parts[1] : '';
    return '${_trOr(l10n, 'call_error_connection_lost_prefix', 'Connection lost. Reconnecting (attempt ')}'
        '$attempt${_trOr(l10n, 'call_error_connection_lost_infix', '/')}$max'
        '${_trOr(l10n, 'call_error_connection_lost_suffix', ')...')}';
  }

  if (key == CallSessionErrorKey.raw) {
    return arg ?? _callErrorKeyToText(l10n, CallSessionErrorKey.unknown);
  }

  return _callErrorKeyToText(l10n, key);
}

class CallRoomScreen extends ConsumerStatefulWidget {
  const CallRoomScreen({super.key});

  @override
  ConsumerState<CallRoomScreen> createState() => _CallRoomScreenState();
}

class _CallRoomScreenState extends ConsumerState<CallRoomScreen>
    with WidgetsBindingObserver {
  final TextEditingController _codeCtrl = TextEditingController();
  Timer? _incomingHideTimer;

  // Whether the floating overlay is actually running for the call this
  // screen is currently managing. Set the moment startGlobalOverlay()
  // succeeds (either right after create/join, or after the user returns
  // from granting the permission in Settings); cleared once the call is
  // no longer connected/reconnecting. This -- not any persisted
  // preference -- is what dispose() consults to decide whether the
  // overlay bubble is actually there to keep the call alive.
  bool _overlayActive = false;
  // True while we've sent the user to Android Settings to grant the
  // overlay permission and are waiting for them to come back, so
  // didChangeAppLifecycleState knows to check and auto-start on resume.
  bool _overlayPendingPermission = false;
  bool _requestingPermissions = false;

  // Captured once, up front -- never via ref.read() inside dispose()
  // itself. flutter_riverpod's ConsumerStatefulElement can already be
  // in a state where ref.read() throws "Cannot use ref after the widget
  // was disposed" by the time dispose() runs (seen in production:
  // Crashlytics issue _CallRoomScreenState.dispose, Bad state on
  // ConsumerStatefulElement.read). ref.read() is documented-safe inside
  // initState(), so grab the controller there and call plain Dart
  // methods on it later -- that sidesteps ref entirely during teardown.
  late final CallSessionController _callCtrl;

  @override
  void initState() {
    super.initState();
    _callCtrl = ref.read(callSessionControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState != AppLifecycleState.resumed) return;
    if (!_overlayPendingPermission) return;
    unawaited(_maybeStartOverlayAfterPermissionReturn());
  }

  Future<void> _maybeStartOverlayAfterPermissionReturn() async {
    _overlayPendingPermission = false;
    if (!Platform.isAndroid) return;

    final granted = await OverlayPlatform.isOverlayPermissionGranted();
    if (!granted || !mounted) return;

    final st = ref.read(callSessionControllerProvider);
    if (!st.connected) return;

    await OverlayPlatform.startGlobalOverlay();
    _overlayActive = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingHideTimer?.cancel();
    _codeCtrl.dispose();

    // Leaving this screen must not leave the LiveKit room connected and
    // the mic hot with nothing left to manage or end it --
    // CallSessionController itself never disconnects on its own
    // disposal (it's a plain, never-auto-disposed StateNotifierProvider,
    // and its own dispose() only cancels a reconnect timer), so unless
    // something here explicitly calls leave(), popping this screen via
    // the back button/gesture -- not just the in-screen "Leave" button
    // -- left the session running indefinitely. On Android, the
    // floating overlay bubble (Platform.isAndroid-gated; see
    // overlay_platform.dart) is the one legitimate way to keep a call
    // connected after leaving this screen: it's backed by a real
    // foreground service declaration and gives the user a visible
    // control to end the call later. iOS has no such mechanism at all
    // (no background audio capability is declared, and there is no
    // overlay), so a call left running after this screen closes on iOS
    // is pure leaked state -- the mic stays live with no way for the
    // user to see or stop it short of force-quitting the app.
    final overlayActivelyTakingOver = Platform.isAndroid && _overlayActive;
    if (!overlayActivelyTakingOver) {
      unawaited(_callCtrl.leave());
    }

    super.dispose();
  }

  // ── AUTOMATIC OVERLAY ACTIVATION ──────────────────────────────────────
  // Called right after a call successfully connects (see
  // _handleCreateRoom()/_handleJoinRoom()) so the floating overlay comes
  // up on its own -- no separate manual toggle, no extra tap. If the
  // permission is already granted (e.g. from an earlier call), this is
  // completely silent. Otherwise it asks once, sends the user to
  // Settings, and _maybeStartOverlayAfterPermissionReturn() finishes the
  // job automatically when they come back.
  Future<void> _ensureOverlayActivation() async {
    if (!Platform.isAndroid) return;
    if (!mounted) return;

    final prefs = ref.read(prefsServiceProvider);
    final granted = await OverlayPlatform.isOverlayPermissionGranted();

    if (granted) {
      if (!prefs.liveOverlayEnabled()) {
        await prefs.setLiveOverlayEnabled(true);
      }
      await OverlayPlatform.startGlobalOverlay();
      _overlayActive = true;
      return;
    }

    if (!mounted) return;
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

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
    _overlayPendingPermission = true;
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
          content: Text(
            '${_trOr(l10n, 'call_room_permission_request_failed_prefix', 'Permission request failed: ')}$e',
          ),
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

    final l10n = context.l10n;
    await ctrl.createAndJoin(
      notificationTitle: _trOr(l10n, 'call_room_notification_title', 'Voice room'),
      notificationTextPrefix:
          _trOr(l10n, 'call_room_notification_text_prefix', 'Room '),
    );

    if (!mounted) return;
    if (ref.read(callSessionControllerProvider).connected) {
      unawaited(_ensureOverlayActivation());
    }
  }

  Future<void> _handleJoinRoom() async {
    final ctrl = ref.read(callSessionControllerProvider.notifier);
    final st = ref.read(callSessionControllerProvider);
    final code = _codeCtrl.text.trim().toUpperCase();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _trOr(context.l10n, 'call_room_enter_room_code', 'Please enter a room code'),
          ),
        ),
      );
      return;
    }

    if (st.joining || st.reconnecting || st.connected) return;

    // Request permissions BEFORE joining room
    final granted = await _requestCallPermissions();
    if (!granted || !mounted) return;

    final l10n = context.l10n;
    await ctrl.joinByCode(
      code,
      notificationTitle: _trOr(l10n, 'call_room_notification_title', 'Voice room'),
      notificationTextPrefix:
          _trOr(l10n, 'call_room_notification_text_prefix', 'Room '),
    );

    if (!mounted) return;
    if (ref.read(callSessionControllerProvider).connected) {
      unawaited(_ensureOverlayActivation());
    }
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

    if (!st.connected && !st.reconnecting && _overlayActive) {
      _overlayActive = false;
    }

    if (st.incomingQuickText != null) {
      _incomingHideTimer?.cancel();
      _incomingHideTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {});
      });
    }

    final quickList = ref.watch(
      overlayQuickMessagesProvider(_localizedDefaultQuickMessages(l10n)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(OverlayPlatform.setOverlayQuickMessages(quickList));
    });

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
                        _trOr(
                          l10n,
                          'call_room_create_or_join_heading',
                          'Create or join with 8-character code',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Platform.isAndroid
                            ? _trOr(
                                l10n,
                                'call_room_create_join_body_overlay_on',
                                'Create a room to get an 8-character code. Share it with your friend to join. Keep talking using the floating overlay over other apps.',
                              )
                            : _trOr(
                                l10n,
                                'call_room_create_join_body_overlay_off',
                                'Create a room to get an 8-character code. Share it with your friend to join. Enable the floating overlay from the top-right button for premium quick controls.',
                              ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (st.hasError) ...[
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
                                  _callErrorText(l10n, st),
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
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: _trOr(
                            l10n,
                            'call_room_enter_code_hint',
                            'Enter 8-character code',
                          ),
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
                                  ? '${_trOr(l10n, 'call_room_connected', 'Connected')}${_trOr(l10n, 'call_room_connected_code_suffix', ' • Code: ')}${st.callId}'
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
