import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/platform/overlay_bridge.dart';
import '../../../core/platform/overlay_platform.dart';
import '../../leagues/services/livekit_service.dart';

final callSessionControllerProvider =
    StateNotifierProvider<CallSessionController, CallSessionState>((ref) {
  return CallSessionController();
});

@immutable
class CallSessionState {
  final bool joining;
  final bool connected;
  final String callId;
  final bool micEnabled;
  final bool micPermissionGranted;
  final String error;
  final bool reconnecting;

  final String? incomingQuickText;
  final String? incomingQuickFrom;
  final int incomingQuickAtMs;

  const CallSessionState({
    required this.joining,
    required this.connected,
    required this.callId,
    required this.micEnabled,
    required this.micPermissionGranted,
    required this.error,
    required this.reconnecting,
    required this.incomingQuickText,
    required this.incomingQuickFrom,
    required this.incomingQuickAtMs,
  });

  factory CallSessionState.initial() => const CallSessionState(
        joining: false,
        connected: false,
        callId: '',
        micEnabled: false,
        micPermissionGranted: false,
        error: '',
        reconnecting: false,
        incomingQuickText: null,
        incomingQuickFrom: null,
        incomingQuickAtMs: 0,
      );

  CallSessionState copyWith({
    bool? joining,
    bool? connected,
    String? callId,
    bool? micEnabled,
    bool? micPermissionGranted,
    String? error,
    bool? reconnecting,
    String? incomingQuickText,
    String? incomingQuickFrom,
    int? incomingQuickAtMs,
  }) {
    return CallSessionState(
      joining: joining ?? this.joining,
      connected: connected ?? this.connected,
      callId: callId ?? this.callId,
      micEnabled: micEnabled ?? this.micEnabled,
      micPermissionGranted: micPermissionGranted ?? this.micPermissionGranted,
      error: error ?? this.error,
      reconnecting: reconnecting ?? this.reconnecting,
      incomingQuickText: incomingQuickText,
      incomingQuickFrom: incomingQuickFrom,
      incomingQuickAtMs: incomingQuickAtMs ?? this.incomingQuickAtMs,
    );
  }
}

class CallSessionController extends StateNotifier<CallSessionState> {
  CallSessionController() : super(CallSessionState.initial()) {
    OverlayBridge.ensureInitialized();
  }

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isHost = false;

  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectBaseDelay = Duration(seconds: 3);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  static final RegExp _codeRe = RegExp(r'^[A-Z0-9]{8}$');

  static String _friendlyError(Object error) {
    if (error is UserFriendlyException) return error.message;
    final msg = error.toString().toLowerCase();
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('unreachable')) {
      return 'Network issue. Please check your connection.';
    }
    if (msg.contains('timeout')) {
      return 'Connection timed out. Please try again.';
    }
    if (msg.contains('permission')) {
      return 'Permission denied. Please check app permissions.';
    }
    if (msg.contains('token') || msg.contains('auth')) {
      return 'Authentication failed. Please sign in again.';
    }
    if (msg.contains('room') || msg.contains('connect')) {
      return 'Could not connect to voice room. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<String> createAndJoin() async {
    final code = _generate8CharCode();
    await joinByCode(code, isHost: true);
    return code;
  }

  Future<void> joinByCode(String code, {bool isHost = false}) async {
    final uid = _uid.trim();
    final callId = code.trim().toUpperCase();

    if (uid.isEmpty) {
      state = state.copyWith(error: 'Please sign in to use voice rooms.');
      return;
    }

    if (!_codeRe.hasMatch(callId)) {
      state = state.copyWith(
        error: 'Room code must be exactly 8 letters/numbers.',
      );
      return;
    }

    if (state.joining) return;

    _isHost = isHost;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();

    state = state.copyWith(
      joining: true,
      error: '',
      reconnecting: false,
      incomingQuickText: null,
      incomingQuickFrom: null,
      incomingQuickAtMs: 0,
      callId: callId,
    );

    await _connectInternal(
      callId: callId,
      uid: uid,
      isHost: isHost,
      isReconnect: false,
    );
  }

  Future<void> _connectInternal({
    required String callId,
    required String uid,
    required bool isHost,
    required bool isReconnect,
  }) async {
    try {
      if (!isReconnect) {
        await _disconnectInternal(clearCode: false);
      }

      var micGranted = false;
      try {
        final st = await Permission.microphone.request();
        micGranted = st.isGranted;
      } catch (_) {}

      state = state.copyWith(micPermissionGranted: micGranted);

      final tok = await LiveKitService.fetchCallToken(
        callId: callId,
        userId: uid,
        isHost: isHost,
      );

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(
            dtx: true,
            audioBitrate: 32000,
          ),
        ),
      );

      _listener = room.createListener();

      _listener!.on<RoomConnectedEvent>((_) {
        _reconnectAttempts = 0;
        state =
            state.copyWith(connected: true, reconnecting: false, error: '');
      });

      _listener!.on<RoomDisconnectedEvent>((_) {
        state = state.copyWith(
          connected: false,
          micEnabled: false,
        );
        unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
        unawaited(OverlayPlatform.stopOverlayVoiceForegroundService());
        _scheduleReconnect();
      });

      _listener!.on<RoomEvent>((event) {
        final type = event.runtimeType.toString().toLowerCase();
        if (!type.contains('data')) return;

        try {
          final dyn = event as dynamic;
          final payload = dyn.payload;
          final participant = dyn.participant;

          String? fromIdentity;
          try {
            fromIdentity = (participant as dynamic).identity?.toString();
          } catch (_) {
            fromIdentity = null;
          }

          final msg = _decodePayload(payload);
          if (msg == null) return;

          final kind = (msg['kind'] ?? '').toString().trim().toLowerCase();
          if (kind != 'quick') return;

          final label = (msg['label'] ?? '').toString().trim();
          if (label.isEmpty) return;

          state = state.copyWith(
            incomingQuickText: label,
            incomingQuickFrom: fromIdentity,
            incomingQuickAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (_) {}
      });

      await room.connect(tok.url, tok.token);

      _room = room;

      if (micGranted) {
        try {
          await room.localParticipant?.setMicrophoneEnabled(true);
          state = state.copyWith(micEnabled: true);
          unawaited(OverlayPlatform.setOverlayMicMutedState(muted: false));
        } catch (_) {
          state = state.copyWith(micEnabled: false);
          unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
        }
      } else {
        state = state.copyWith(micEnabled: false);
        unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
      }

      _registerOverlayHandlers();

      unawaited(
        OverlayPlatform.startOverlayVoiceForegroundService(
          title: 'Voice room',
          text: 'Room $callId',
        ),
      );

      state = state.copyWith(
        joining: false,
        connected: true,
        reconnecting: false,
        error: '',
      );
    } catch (e) {
      final friendly = _friendlyError(e is Object ? e : Exception('unknown'));
      if (isReconnect) {
        state = state.copyWith(
          reconnecting: true,
          error: 'Reconnecting... $friendly',
        );
        _scheduleReconnect();
      } else {
        state = state.copyWith(
          joining: false,
          connected: false,
          reconnecting: false,
          error: friendly,
        );
      }
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
    }
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    if (state.callId.isEmpty) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      state = state.copyWith(
        reconnecting: false,
        error: 'Could not reconnect. Please rejoin manually.',
      );
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    final delay = _reconnectBaseDelay * _reconnectAttempts;

    state = state.copyWith(
      reconnecting: true,
      error:
          'Connection lost. Reconnecting (attempt $_reconnectAttempts/$_maxReconnectAttempts)...',
    );

    _reconnectTimer = Timer(delay, () {
      if (!mounted) return;
      if (state.callId.isEmpty) return;

      final uid = _uid.trim();
      if (uid.isEmpty) return;

      _connectInternal(
        callId: state.callId,
        uid: uid,
        isHost: _isHost,
        isReconnect: true,
      );
    });
  }

  Future<void> leave() async {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    await _disconnectInternal(clearCode: true);
    state = CallSessionState.initial();
    unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
  }

  Future<void> toggleMic() async {
    final room = _room;
    if (room == null) return;
    if (!state.micPermissionGranted) return;

    final next = !state.micEnabled;
    await setMicEnabled(next);
  }

  Future<void> setMicEnabled(bool enabled) async {
    final room = _room;
    if (room == null) return;
    if (!state.micPermissionGranted) return;

    try {
      await room.localParticipant?.setMicrophoneEnabled(enabled);
      state = state.copyWith(micEnabled: enabled);
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: !enabled));
    } catch (_) {}
  }

  Future<void> sendQuick(String label) async {
    final room = _room;
    if (room == null) return;
    if (!state.connected) return;

    final cleaned = label.trim();
    if (cleaned.isEmpty) return;

    final payload = <String, dynamic>{
      'kind': 'quick',
      'label': cleaned,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    try {
      room.localParticipant?.publishData(bytes, reliable: true);
    } catch (_) {
      try {
        room.localParticipant?.publishData(bytes);
      } catch (_) {}
    }
  }

  void _registerOverlayHandlers() {
    OverlayBridge.toggleMic = () async {
      await toggleMic();
    };

    OverlayBridge.setMicEnabled = (enabled) async {
      await setMicEnabled(enabled);
    };

    OverlayBridge.endSession = () async {
      await leave();
    };

    OverlayBridge.sendQuick = (label) async {
      await sendQuick(label);
    };
  }

  Future<void> _disconnectInternal({required bool clearCode}) async {
    OverlayBridge.clearHandlers();
    unawaited(OverlayPlatform.stopOverlayVoiceForegroundService());

    try {
      _listener?.dispose();
    } catch (_) {}
    _listener = null;

    try {
      await _room?.disconnect();
    } catch (_) {}
    try {
      await _room?.dispose();
    } catch (_) {}

    _room = null;

    state = state.copyWith(
      joining: false,
      connected: false,
      micEnabled: false,
      error: '',
      callId: clearCode ? '' : state.callId,
      incomingQuickText: null,
      incomingQuickFrom: null,
      incomingQuickAtMs: 0,
    );
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    super.dispose();
  }

  static Map<String, dynamic>? _decodePayload(dynamic payload) {
    try {
      if (payload is Uint8List) {
        final s = utf8.decode(payload);
        final j = jsonDecode(s);
        if (j is Map<String, dynamic>) return j;
        if (j is Map) return j.cast<String, dynamic>();
      }
      if (payload is List<int>) {
        final s = utf8.decode(Uint8List.fromList(payload));
        final j = jsonDecode(s);
        if (j is Map<String, dynamic>) return j;
        if (j is Map) return j.cast<String, dynamic>();
      }
      if (payload is String) {
        final j = jsonDecode(payload);
        if (j is Map<String, dynamic>) return j;
        if (j is Map) return j.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  static String _generate8CharCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(
      8,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
  }
}
