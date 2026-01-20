import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import 'local_signaling.dart';

enum LocalLiveViewerState {
  idle,
  connecting,
  negotiating,
  connected,
  stopped,
  error,
}

class LocalLiveViewerSession {
  LocalLiveViewerSession({
    required this.liveMatchId,
    required this.host,
    required this.port,
  }) : viewerId = const Uuid().v4();

  final String liveMatchId;
  final String host;
  final int port;

  final String viewerId;

  final ValueNotifier<LocalLiveViewerState> state =
      ValueNotifier<LocalLiveViewerState>(LocalLiveViewerState.idle);

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  final RTCVideoRenderer screenRenderer = RTCVideoRenderer();
  final RTCVideoRenderer cameraRenderer = RTCVideoRenderer();

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  LocalSignalingClient? _client;
  StreamSubscription? _clientSub;

  RTCPeerConnection? _pc;
  RTCDataChannel? _eventsChannel;

  String? _screenTrackId;
  String? _cameraTrackId;

  MediaStream? _remoteScreenStream;
  MediaStream? _remoteCameraStream;

  final Map<String, MediaStreamTrack> _pendingVideoTracks = {};

  Future<void> connect() async {
    if (_client != null) return;

    state.value = LocalLiveViewerState.connecting;
    error.value = null;

    try {
      await screenRenderer.initialize();
      await cameraRenderer.initialize();

      _client = LocalSignalingClient(
        host: host,
        port: port,
        matchId: liveMatchId,
        viewerId: viewerId,
      );
      await _client!.connect();
      _clientSub = _client!.messages.listen(_onHostSignal);

      _pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': <Map<String, dynamic>>[],
      });

      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        _client?.send({
          'type': 'candidate',
          'candidate': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        });
      };

      _pc!.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          state.value = LocalLiveViewerState.connected;
        }
      };

      _pc!.onDataChannel = (ch) {
        _eventsChannel = ch;
        _eventsChannel!.onMessage = (m) => _onDataChannelMessage(m.text);
      };

      _pc!.onTrack = (event) async {
        final track = event.track;
        if (track.kind != 'video') return;

        // flutter_webrtc may expose track.id as nullable
        final String? id = track.id;
        if (id == null || id.isEmpty) return;

        _pendingVideoTracks[id] = track;
        await _tryAttachTracks();
      };
    } catch (e) {
      state.value = LocalLiveViewerState.error;
      error.value = e.toString();
      await disconnect();
      rethrow;
    }
  }

  Future<void> _onHostSignal(JsonMap msg) async {
    final type = msg['type']?.toString();

    if (type == 'error') {
      state.value = LocalLiveViewerState.error;
      error.value = (msg['message'] ?? 'Unknown signaling error').toString();
      return;
    }

    if (type == 'offer') {
      final sdp = msg['sdp'] as String?;
      if (sdp == null) return;

      state.value = LocalLiveViewerState.negotiating;

      await _pc?.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });

      await _pc!.setLocalDescription(answer);

      _client?.send({'type': 'answer', 'sdp': answer.sdp});
      return;
    }

    if (type == 'candidate') {
      final c = msg['candidate'] as Map?;
      if (c == null) return;
      await _pc?.addCandidate(
        RTCIceCandidate(
          c['candidate'] as String?,
          c['sdpMid'] as String?,
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ),
      );
      return;
    }
  }

  void _onDataChannelMessage(String text) {
    try {
      final msg = jsonDecode(text) as Map<String, dynamic>;

      if (msg['type'] == 'tracks') {
        _screenTrackId =
            (msg['screenVideoTrackId'] as String?)?.trim();
        _cameraTrackId =
            (msg['cameraVideoTrackId'] as String?)?.trim();
        _tryAttachTracks();
        return;
      }

      if (msg['type'] == 'event') {
        final event =
            (msg['event'] as Map?)?.cast<String, dynamic>();
        if (event != null) _events.add(event);
        return;
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _tryAttachTracks() async {
    if (_screenTrackId != null && _screenTrackId!.isNotEmpty) {
      final t = _pendingVideoTracks[_screenTrackId!];
      if (t != null) {
        _remoteScreenStream ??=
            await createLocalMediaStream('remote-screen');
        _remoteScreenStream!.addTrack(t);
        screenRenderer.srcObject = _remoteScreenStream;
      }
    }

    if (_cameraTrackId != null && _cameraTrackId!.isNotEmpty) {
      final t = _pendingVideoTracks[_cameraTrackId!];
      if (t != null) {
        _remoteCameraStream ??=
            await createLocalMediaStream('remote-camera');
        _remoteCameraStream!.addTrack(t);
        cameraRenderer.srcObject = _remoteCameraStream;
      }
    }
  }

  void sendChat(String text) =>
      sendEvent({'kind': 'chat', 'text': text});
  void sendReaction(String reaction) =>
      sendEvent({'kind': 'reaction', 'reaction': reaction});

  void sendEvent(Map<String, dynamic> event) {
    final dc = _eventsChannel;
    if (dc == null) return;
    if (dc.state != RTCDataChannelState.RTCDataChannelOpen) return;

    final payload =
        jsonEncode({'type': 'event', 'event': event});
    try {
      dc.send(RTCDataChannelMessage(payload));
    } catch (_) {}
  }

  /// Toggle remote audio (what viewer hears)
  void setRemoteAudioEnabled(bool enabled) {
    try {
      final tracks =
          _remoteCameraStream?.getAudioTracks() ??
              const <MediaStreamTrack>[];
      for (final t in tracks) {
        t.enabled = enabled;
      }
    } catch (_) {}
  }

  Future<void> disconnect() async {
    state.value = LocalLiveViewerState.stopped;

    try {
      await _clientSub?.cancel();
    } catch (_) {}
    _clientSub = null;

    try {
      await _eventsChannel?.close();
    } catch (_) {}
    _eventsChannel = null;

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      await _remoteScreenStream?.dispose();
    } catch (_) {}
    _remoteScreenStream = null;

    try {
      await _remoteCameraStream?.dispose();
    } catch (_) {}
    _remoteCameraStream = null;

    try {
      await _client?.close();
    } catch (_) {}
    _client = null;

    screenRenderer.srcObject = null;
    cameraRenderer.srcObject = null;

    try {
      await screenRenderer.dispose();
    } catch (_) {}
    try {
      await cameraRenderer.dispose();
    } catch (_) {}

    try {
      await _events.close();
    } catch (_) {}
  }
}
