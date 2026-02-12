import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import 'local_signaling.dart';

/// User-safe exception: if UI accidentally shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

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

  final ValueNotifier<LocalLiveViewerState> state = ValueNotifier<LocalLiveViewerState>(LocalLiveViewerState.idle);

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// What the viewer sees
  final RTCVideoRenderer screenRenderer = RTCVideoRenderer();
  final RTCVideoRenderer cameraRenderer = RTCVideoRenderer();

  /// Events from host/viewers (chat, reactions, mic, etc.)
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  LocalSignalingClient? _client;
  StreamSubscription? _clientSub;

  RTCPeerConnection? _pc;
  RTCDataChannel? _eventsChannel;

  /// Remote media streams (assigned from onTrack)
  MediaStream? _remoteScreenStream;
  MediaStream? _remoteCameraStream;

  Future<void> _requireSignedInAndOnline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }

    await ConnectivityService.instance.initialize();
    final ok = await ConnectivityService.instance.recheckConnection(timeout: const Duration(seconds: 4));
    if (!ok) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
  }

  Never _fail(Object e) {
    final msg = UserFriendlyError.toMessage(e);
    state.value = LocalLiveViewerState.error;
    error.value = msg;
    throw UserFriendlyException(msg);
  }

  Future<void> connect() async {
    if (_client != null) return;

    state.value = LocalLiveViewerState.connecting;
    error.value = null;

    // ONLINE-ONLY: never allow local live viewer to operate offline.
    await _requireSignedInAndOnline();

    try {
      await screenRenderer.initialize();
      await cameraRenderer.initialize();

      _client = LocalSignalingClient(
        host: host,
        port: port,
        matchId: liveMatchId,
        viewerId: viewerId,
      );
      await _client!.connect().timeout(const Duration(seconds: 12));
      _clientSub = _client!.messages.listen(_onHostSignal);

      _pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': <Map<String, dynamic>>[],
      }).timeout(const Duration(seconds: 12));

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

      // Attach remote streams: distinguish screen vs camera
      _pc!.onTrack = (event) async {
        if (event.streams.isEmpty) return;
        final stream = event.streams.first;

        if (kDebugMode) {
          debugPrint(
            '[Viewer] onTrack kind=${event.track.kind} '
            'streamId=${stream.id} '
            'video=${stream.getVideoTracks().length} '
            'audio=${stream.getAudioTracks().length}',
          );
        }

        // Ignore streams without video
        if (stream.getVideoTracks().isEmpty) return;

        final hasAudio = stream.getAudioTracks().isNotEmpty;

        if (!hasAudio) {
          // This is the screen share: video-only
          if (_remoteScreenStream == null || _remoteScreenStream!.id != stream.id) {
            _remoteScreenStream = stream;
            screenRenderer.srcObject = _remoteScreenStream;
            if (kDebugMode) {
              debugPrint('[Viewer] Attached SCREEN stream ${stream.id}');
            }
          }
        } else {
          // This is the camera + mic stream
          if (_remoteCameraStream == null || _remoteCameraStream!.id != stream.id) {
            _remoteCameraStream = stream;
            cameraRenderer.srcObject = _remoteCameraStream;
            if (kDebugMode) {
              debugPrint('[Viewer] Attached CAMERA stream ${stream.id}');
            }
          }
        }
      };
    } on UserFriendlyException catch (e) {
      _fail(e);
    } catch (e) {
      _fail(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> _onHostSignal(JsonMap msg) async {
    final type = msg['type']?.toString();

    if (type == 'error') {
      // Never trust/forward raw signaling server messages to UI.
      state.value = LocalLiveViewerState.error;
      error.value = "We couldn't connect right now. Please try again.";
      return;
    }

    if (type == 'offer') {
      final sdp = msg['sdp'] as String?;
      if (sdp == null) return;

      state.value = LocalLiveViewerState.negotiating;

      try {
        await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'offer')).timeout(const Duration(seconds: 12));

        final answer = await _pc!.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': true,
        }).timeout(const Duration(seconds: 12));

        await _pc!.setLocalDescription(answer).timeout(const Duration(seconds: 12));

        _client?.send({'type': 'answer', 'sdp': answer.sdp});
      } catch (e) {
        _fail(e is Object ? e : Exception('unknown'));
      }
      return;
    }

    if (type == 'candidate') {
      final c = msg['candidate'] as Map?;
      if (c == null) return;
      try {
        await _pc?.addCandidate(
          RTCIceCandidate(
            c['candidate'] as String?,
            c['sdpMid'] as String?,
            (c['sdpMLineIndex'] as num?)?.toInt(),
          ),
        );
      } catch (e) {
        _fail(e is Object ? e : Exception('unknown'));
      }
      return;
    }
  }

  void _onDataChannelMessage(String text) {
    try {
      final msg = jsonDecode(text) as Map<String, dynamic>;

      if (msg['type'] == 'tracks') {
        // We no longer rely on track IDs; screen/camera
        // are detected by stream audio in onTrack.
        return;
      }

      if (msg['type'] == 'event') {
        final event = (msg['event'] as Map?)?.cast<String, dynamic>();
        if (event != null) _events.add(event);
        return;
      }
    } catch (_) {
      // ignore malformed messages
    }
  }

  void sendChat(String text) => sendEvent({'kind': 'chat', 'text': text});
  void sendReaction(String reaction) => sendEvent({'kind': 'reaction', 'reaction': reaction});

  void sendEvent(Map<String, dynamic> event) {
    final dc = _eventsChannel;
    if (dc == null) return;
    if (dc.state != RTCDataChannelState.RTCDataChannelOpen) return;

    final payload = jsonEncode({'type': 'event', 'event': event});
    try {
      dc.send(RTCDataChannelMessage(payload));
    } catch (_) {}
  }

  /// Toggle remote audio (what viewer hears) – camera/mic audio.
  void setRemoteAudioEnabled(bool enabled) {
    try {
      final tracks = _remoteCameraStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
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
