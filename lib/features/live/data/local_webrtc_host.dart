import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'live_quality.dart';
import 'local_discovery.dart';
import 'local_lan_ip.dart';
import 'local_signaling.dart';

enum LocalLiveHostState {
  idle,
  starting,
  waitingForViewers,
  connected,
  stopped,
  error,
}

class LocalLiveHostSession {
  LocalLiveHostSession({
    required this.liveMatchId,
    required this.port,
    required this.captureConfig,
    this.homeName,
    this.awayName,
    this.side = LiveHostSide.unknown,
  });

  final String liveMatchId;
  final int port;

  final LiveCaptureConfig captureConfig;

  /// Optional labels for discovery + UI
  final String? homeName;
  final String? awayName;
  final LiveHostSide side;

  final ValueNotifier<LocalLiveHostState> state =
      ValueNotifier<LocalLiveHostState>(LocalLiveHostState.idle);

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<int> viewerCount = ValueNotifier<int>(0);
  final ValueNotifier<String?> hostIp = ValueNotifier<String?>(null);

  final ValueNotifier<bool> micEnabled = ValueNotifier<bool>(true);

  final RTCVideoRenderer screenRenderer = RTCVideoRenderer();
  final RTCVideoRenderer cameraRenderer = RTCVideoRenderer();

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  LocalSignalingServer? _server;
  StreamSubscription? _serverSub;

  LocalLiveDiscoveryBroadcaster? _broadcaster;

  MediaStream? _screenStream;
  MediaStream? _cameraStream;

  final Map<String, _ViewerPeer> _peers = {}; // viewerId -> peer

  Future<void> start() async {
    if (_server != null) return;

    state.value = LocalLiveHostState.starting;
    error.value = null;

    try {
      await screenRenderer.initialize();
      await cameraRenderer.initialize();

      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final denied = statuses.entries.where((e) => !e.value.isGranted).toList();
      if (denied.isNotEmpty) {
        throw Exception(
            'Permissions denied: ${denied.map((e) => e.key).join(', ')}');
      }

      hostIp.value = await LocalLanIp.findLocalIpv4();

      _server = LocalSignalingServer(port: port, matchId: liveMatchId);
      await _server!.start();
      _serverSub = _server!.messages.listen(_onSignalMessage);

      _server!.viewerCount.addListener(() {
        viewerCount.value = _server!.viewerCount.value;
      });

      // Discovery includes match labels + side
      _broadcaster = LocalLiveDiscoveryBroadcaster(
        matchId: liveMatchId,
        port: port,
        homeName: homeName,
        awayName: awayName,
        side: side,
      );
      await _broadcaster!.start();

      // Screen capture (try constraints; fallback to simple)
      try {
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': {
            'frameRate': captureConfig.screenFps,
            'width': captureConfig.screenWidth,
            'height': captureConfig.screenHeight,
          },
          'audio': false,
        });
      } catch (_) {
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': true,
          'audio': false,
        });
      }

      // Front camera + mic
      _cameraStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': captureConfig.cameraWidth,
          'height': captureConfig.cameraHeight,
          'frameRate': captureConfig.cameraFps,
        },
      });

      // DEBUG: print track info
      if (kDebugMode) {
        final sv = _screenStream?.getVideoTracks().length ?? 0;
        final sa = _screenStream?.getAudioTracks().length ?? 0;
        final cv = _cameraStream?.getVideoTracks().length ?? 0;
        final ca = _cameraStream?.getAudioTracks().length ?? 0;
        print('[Host] Screen tracks: video=$sv audio=$sa');
        print('[Host] Camera tracks: video=$cv audio=$ca');
      }

      // Ensure screen capture actually has a video track
      final screenVideoTracks = _screenStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
      if (screenVideoTracks.isEmpty) {
        throw Exception(
          'Screen capture returned no video track. '
          'Check screen recording permission or device support.',
        );
      }

      screenRenderer.srcObject = _screenStream;
      cameraRenderer.srcObject = _cameraStream;

      // Apply initial mic state
      _applyMicEnabled(micEnabled.value);

      state.value = LocalLiveHostState.waitingForViewers;
    } catch (e) {
      if (kDebugMode) {
        print('[Host] ERROR in start(): $e');
      }
      state.value = LocalLiveHostState.error;
      error.value = e.toString();
      await stop();
      rethrow;
    }
  }

  void _applyMicEnabled(bool enabled) {
    try {
      final tracks = _cameraStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
      for (final t in tracks) {
        t.enabled = enabled;
      }
    } catch (_) {}
  }

  /// Can be called while streaming; works on most devices.
  Future<void> setMicEnabled(bool enabled) async {
    micEnabled.value = enabled;
    _applyMicEnabled(enabled);

    // Inform viewers (optional UI sync)
    broadcastEvent({
      'kind': 'mic',
      'enabled': enabled,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _onSignalMessage(JsonMap msg) async {
    final type = msg['type']?.toString();
    final viewerId = msg['viewerId']?.toString();

    if (type == 'viewer-connected') {
      if (viewerId == null) return;
      await addViewerIfNeeded(viewerId);
      return;
    }

    if (type == 'viewer-disconnected') {
      if (viewerId == null) return;
      await _removeViewer(viewerId);
      return;
    }

    if (viewerId == null) return;

    if (type == 'answer') {
      final peer = _peers[viewerId];
      final sdp = msg['sdp'] as String?;
      if (peer == null || sdp == null) return;
      await peer.pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      return;
    }

    if (type == 'candidate') {
      final peer = _peers[viewerId];
      final c = msg['candidate'] as Map?;
      if (peer == null || c == null) return;

      await peer.pc.addCandidate(
        RTCIceCandidate(
          c['candidate'] as String?,
          c['sdpMid'] as String?,
          (c['sdpMLineIndex'] as num?)?.toInt(),
        ),
      );
      return;
    }
  }

  Future<void> addViewerIfNeeded(String viewerId) async {
    if (_peers.containsKey(viewerId)) return;

    final server = _server;
    if (server == null) return;

    final pc = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
      'iceServers': <Map<String, dynamic>>[],
    });

    final peer = _ViewerPeer(viewerId: viewerId, pc: pc);
    _peers[viewerId] = peer;

    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      server.sendToViewer(viewerId, {
        'type': 'candidate',
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };

    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        state.value = LocalLiveHostState.connected;
      }
    };

    final dc = await pc.createDataChannel(
      'events',
      RTCDataChannelInit()..ordered = true,
    );
    peer.eventsChannel = dc;

    dc.onDataChannelState = (s) {
      if (kDebugMode) {
        print('[Host] DataChannel state for $viewerId: $s');
      }
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _sendTrackMappingToViewer(viewerId);

        // Send initial mic state too
        broadcastEvent({
          'kind': 'mic',
          'enabled': micEnabled.value,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
      }
    };

    dc.onMessage = (m) {
      _onViewerDataChannelMessage(viewerId, m.text);
    };

    final screenStream = _screenStream;
    final cameraStream = _cameraStream;

    if (screenStream != null) {
      for (final t in screenStream.getVideoTracks()) {
        if (kDebugMode) {
          print('[Host] Adding SCREEN video track ${t.id} to viewer $viewerId');
        }
        pc.addTrack(t, screenStream);
      }
    }

    if (cameraStream != null) {
      for (final t in cameraStream.getVideoTracks()) {
        if (kDebugMode) {
          print('[Host] Adding CAMERA video track ${t.id} to viewer $viewerId');
        }
        pc.addTrack(t, cameraStream);
      }
      for (final t in cameraStream.getAudioTracks()) {
        if (kDebugMode) {
          print('[Host] Adding CAMERA audio track ${t.id} to viewer $viewerId');
        }
        pc.addTrack(t, cameraStream);
      }
    }

    final offer = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });

    await pc.setLocalDescription(offer);

    server.sendToViewer(viewerId, {
      'type': 'offer',
      'sdp': offer.sdp,
    });
  }

  void _onViewerDataChannelMessage(String viewerId, String text) {
    try {
      final msg = jsonDecode(text) as Map<String, dynamic>;
      if (msg['type'] != 'event') return;

      final event = (msg['event'] as Map?)?.cast<String, dynamic>();
      if (event == null) return;

      final enriched = <String, dynamic>{
        ...event,
        'from': viewerId,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

      _events.add(enriched);
      broadcastEvent(enriched);
    } catch (_) {
      // ignore
    }
  }

  void _sendTrackMappingToViewer(String viewerId) {
    final screenTracks =
        _screenStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    final cameraTracks =
        _cameraStream?.getVideoTracks() ?? const <MediaStreamTrack>[];

    final screenTrackId = screenTracks.isNotEmpty ? screenTracks.first.id : null;
    final cameraTrackId = cameraTracks.isNotEmpty ? cameraTracks.first.id : null;

    if (kDebugMode) {
      print('[Host] sendTrackMappingToViewer($viewerId) '
          'screenTrackId=$screenTrackId cameraTrackId=$cameraTrackId');
    }

    if (screenTrackId == null ||
        screenTrackId.isEmpty ||
        cameraTrackId == null ||
        cameraTrackId.isEmpty) {
      return;
    }

    final payload = jsonEncode({
      'type': 'tracks',
      'screenVideoTrackId': screenTrackId,
      'cameraVideoTrackId': cameraTrackId,
    });

    _peers[viewerId]?.eventsChannel?.send(RTCDataChannelMessage(payload));
  }

  void broadcastEvent(Map<String, dynamic> event) {
    final payload = jsonEncode({'type': 'event', 'event': event});
    for (final peer in _peers.values) {
      final dc = peer.eventsChannel;
      if (dc == null) continue;
      if (dc.state != RTCDataChannelState.RTCDataChannelOpen) continue;
      try {
        dc.send(RTCDataChannelMessage(payload));
      } catch (_) {}
    }
  }

  Future<void> _removeViewer(String viewerId) async {
    final peer = _peers.remove(viewerId);
    if (peer == null) return;

    try {
      await peer.eventsChannel?.close();
    } catch (_) {}

    try {
      await peer.pc.close();
    } catch (_) {}
  }

  Future<void> stop() async {
    state.value = LocalLiveHostState.stopped;

    try {
      await _serverSub?.cancel();
    } catch (_) {}
    _serverSub = null;

    for (final id in _peers.keys.toList()) {
      await _removeViewer(id);
    }
    _peers.clear();

    try {
      await _broadcaster?.stop();
    } catch (_) {}
    _broadcaster = null;

    try {
      await _screenStream?.dispose();
    } catch (_) {}
    _screenStream = null;

    try {
      await _cameraStream?.dispose();
    } catch (_) {}
    _cameraStream = null;

    screenRenderer.srcObject = null;
    cameraRenderer.srcObject = null;

    try {
      await screenRenderer.dispose();
    } catch (_) {}
    try {
      await cameraRenderer.dispose();
    } catch (_) {}

    try {
      await _server?.stop();
    } catch (_) {}
    _server = null;

    try {
      await _events.close();
    } catch (_) {}
  }
}

class _ViewerPeer {
  _ViewerPeer({required this.viewerId, required this.pc});
  final String viewerId;
  final RTCPeerConnection pc;
  RTCDataChannel? eventsChannel;
}
