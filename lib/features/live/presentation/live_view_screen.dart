import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/services/livekit_service.dart';
import '../data/foreground_streaming_service.dart';
import '../data/local_discovery.dart';
import 'battery_optimization_guide.dart';
import 'widgets/live_floating_quick_message.dart';

enum _PrimarySide { home, away }
enum _ViewerLayoutMode { single, dual }

class LiveViewScreen extends ConsumerStatefulWidget {
  const LiveViewScreen({
    super.key,
    required this.matchId,
    required this.isHost,
    this.hostAddress, // legacy (ignored for online)
    this.port, // legacy (ignored for online)
    this.homeName,
    this.awayName,
    this.hostSide,
  });

  final String matchId;
  final bool isHost;
  final String? hostAddress;
  final int? port;
  final String? homeName;
  final String? awayName;
  final String? hostSide;

  @override
  ConsumerState<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends ConsumerState<LiveViewScreen> {
  static const MethodChannel _liveChannel = MethodChannel('local_live');

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Timer? _pollTimer;

  bool _busy = false;
  String? _errorText;

  bool _connected = false;
  String? _roomName;

  String _uid = '';

  _PrimarySide _primary = _PrimarySide.home;

  bool _viewerAudioEnabled = true;
  _ViewerLayoutMode _viewerLayoutMode = _ViewerLayoutMode.single;
  bool _isFullscreen = false;

  bool _hostMicEnabled = true;
  bool _hostCameraEnabled = true;
  bool _hostScreenEnabled = false;

  // If true, host will start screen sharing right after "Start Broadcast"
  // (Android will show a system prompt; user must accept).
  final bool _autoStartScreenShareOnBroadcast = true;

  // Incoming quick message overlay
  Timer? _incomingQuickTimer;
  String? _incomingQuickText;
  String? _incomingQuickFrom;

  static const List<String> _quickMessages = <String>[
    'Focus!',
    'Calm down',
    'We got this',
    'One more goal!',
    'Don’t give up',
    'Sorry',
    'Unlucky',
    'What a goal!',
    'Ref??',
  ];

  String get _homeLabel =>
      (widget.homeName?.trim().isNotEmpty == true) ? widget.homeName!.trim() : 'HOME';
  String get _awayLabel =>
      (widget.awayName?.trim().isNotEmpty == true) ? widget.awayName!.trim() : 'AWAY';

  LiveHostSide get _mySide => parseLiveHostSide(widget.hostSide);

  @override
  void initState() {
    super.initState();

    final prefs = ref.read(prefsServiceProvider);
    _uid = prefs.getCurrentUserId() ?? '';

    if (!widget.isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _connectOnline(publishIfHost: false);
      });
    }
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }

    _incomingQuickTimer?.cancel();
    _pollTimer?.cancel();
    _disconnectRoom();
    super.dispose();
  }

  // Do NOT request overlay permission automatically.
  Future<void> _maybeStartOverlayBubbleIfGranted() async {
    if (!Platform.isAndroid) return;
    final prefs = ref.read(prefsServiceProvider);
    if (!prefs.liveOverlayEnabled()) return;

    try {
      final bool granted =
          await _liveChannel.invokeMethod<bool>('isOverlayPermissionGranted') ?? false;
      if (!granted) return;
      await _liveChannel.invokeMethod('startLiveOverlayBubble');
    } catch (_) {}
  }

  Future<void> _stopOverlayBubble() async {
    if (!Platform.isAndroid) return;
    try {
      await _liveChannel.invokeMethod('stopLiveOverlayBubble');
    } catch (_) {}
  }

  Future<void> _startHostForegroundService() async {
    if (!widget.isHost) return;
    try {
      final title = 'Live: ${_homeLabel.isNotEmpty ? _homeLabel : ''}'
          '${_awayLabel.isNotEmpty ? ' vs $_awayLabel' : ''}'.trim();
      await ForegroundStreamingService.start(
        matchId: widget.matchId,
        title: title.isEmpty ? 'Live match: ${widget.matchId}' : title,
        text: 'Broadcasting online • Keep app alive in background',
      );
    } catch (_) {
      // If this fails, Android may kill the app in background.
      // We keep going, but user might see "starts fresh" when minimized.
    }
  }

  Future<void> _stopHostForegroundService() async {
    if (!widget.isHost) return;
    try {
      await ForegroundStreamingService.stop();
    } catch (_) {}
  }

  Future<void> _connectOnline({required bool publishIfHost}) async {
    if (_busy) return;

    if (_uid.trim().isEmpty) {
      setState(() {
        _errorText = 'Missing user ID. Please login/restart so current_user_id is set.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      await _disconnectRoom();

      final tok = await LiveKitService.fetchMatchToken(
        matchId: widget.matchId,
        userId: _uid,
        isHost: widget.isHost,
        side: liveHostSideToWire(_mySide),
      );

      _roomName = tok.roomName;

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      _listener = room.createListener();

      _listener!.on<RoomConnectedEvent>((event) {
        if (!mounted) return;
        setState(() => _connected = true);
      });

      _listener!.on<RoomDisconnectedEvent>((event) {
        if (!mounted) return;
        setState(() => _connected = false);
        if (widget.isHost) {
          ForegroundStreamingService.stop();
        }
      });

      // Data event handling (quick messages)
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

          final msg = _decodeQuickPayload(payload);
          if (msg == null) return;

          final to = (msg['to'] ?? '').toString().trim().toLowerCase();
          final fromSide = (msg['fromSide'] ?? '').toString().trim().toLowerCase();
          final label = (msg['label'] ?? '').toString();

          if (label.trim().isEmpty) return;

          final my = liveHostSideToWire(_mySide).toLowerCase();

          if (to.isNotEmpty && my.isNotEmpty && my != 'unknown') {
            if (to != my) return;
          } else {
            if (my != 'unknown' && fromSide.isNotEmpty && fromSide == my) return;
          }

          _showIncomingQuick(
            label,
            from: fromIdentity ?? (fromSide.isNotEmpty ? fromSide.toUpperCase() : null),
          );
        } catch (_) {}
      });

      await room.connect(tok.url, tok.token);

      if (!mounted) return;

      setState(() {
        _room = room;
        _connected = true;
      });

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        if (!mounted) return;
        setState(() {});
        _applyViewerAudioSetting();
      });

      await _maybeStartOverlayBubbleIfGranted();

      if (publishIfHost && widget.isHost) {
        await _startHostForegroundService();
        await _ensureHostPublishing();

        if (_autoStartScreenShareOnBroadcast) {
          // This will show Android “Start now” prompt; user must accept.
          await _setHostScreenShareEnabled(true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Map<String, dynamic>? _decodeQuickPayload(dynamic payload) {
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

  void _showIncomingQuick(String text, {String? from}) {
    _incomingQuickTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _incomingQuickText = text;
      _incomingQuickFrom = from;
    });

    _incomingQuickTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _incomingQuickText = null;
        _incomingQuickFrom = null;
      });
    });
  }

  Future<void> _ensureHostPublishing() async {
    final room = _room;
    if (room == null) return;

    try {
      await Permission.microphone.request();
    } catch (_) {}
    try {
      await Permission.camera.request();
    } catch (_) {}

    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
      _hostMicEnabled = true;
    } catch (_) {}

    try {
      await room.localParticipant?.setCameraEnabled(true);
      _hostCameraEnabled = true;
    } catch (_) {}

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setHostScreenShareEnabled(bool enabled) async {
    final room = _room;
    if (room == null) return;

    try {
      await room.localParticipant?.setScreenShareEnabled(enabled);
      if (!mounted) return;
      setState(() => _hostScreenEnabled = enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hostScreenEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Screen share failed: $e')),
      );
    }
  }

  Future<void> _disconnectRoom() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    try {
      _listener?.dispose();
    } catch (_) {}
    _listener = null;

    final r = _room;
    _room = null;

    try {
      await r?.disconnect();
    } catch (_) {}
    try {
      await r?.dispose();
    } catch (_) {}

    _connected = false;

    await _stopOverlayBubble();
    await _stopHostForegroundService();
  }

  VideoTrack? _videoTrackFromParticipant(dynamic p, {TrackSource? preferredSource}) {
    try {
      final pubs = (p as dynamic).videoTrackPublications;
      Iterable<dynamic> videoPubs = const [];
      if (pubs is Iterable) {
        videoPubs = pubs.cast<dynamic>();
      } else if (pubs is Map) {
        videoPubs = pubs.values.cast<dynamic>();
      }

      if (preferredSource != null) {
        for (final pub in videoPubs) {
          final track = (pub as dynamic).track;
          if (track == null) continue;
          final src = (pub as dynamic).source;
          if (src == preferredSource) return track as VideoTrack;
        }
      }

      for (final pub in videoPubs) {
        final track = (pub as dynamic).track;
        if (track == null) continue;
        return track as VideoTrack;
      }
    } catch (_) {}
    return null;
  }

  LiveHostSide _sideFromParticipant(dynamic p) {
    try {
      final meta = (p as dynamic).metadata;
      if (meta is String && meta.trim().isNotEmpty) {
        final decoded = jsonDecode(meta) as Map<String, dynamic>;
        final side = (decoded['side'] ?? '').toString().trim().toLowerCase();
        if (side == 'home') return LiveHostSide.home;
        if (side == 'away') return LiveHostSide.away;
      }
    } catch (_) {}
    return LiveHostSide.unknown;
  }

  VideoTrack? _localVideo(TrackSource preferredSource) {
    final room = _room;
    if (room == null) return null;
    final lp = room.localParticipant;
    if (lp == null) return null;
    return _videoTrackFromParticipant(lp, preferredSource: preferredSource);
  }

  VideoTrack? _remoteVideoForSide(LiveHostSide side, TrackSource preferredSource) {
    final room = _room;
    if (room == null) return null;

    try {
      final remotes = room.remoteParticipants;
      final participants = remotes.values;

      for (final p in participants) {
        final ps = _sideFromParticipant(p);
        if (ps != side) continue;
        final t = _videoTrackFromParticipant(p, preferredSource: preferredSource);
        if (t != null) return t;
      }

      for (final p in participants) {
        final ps = _sideFromParticipant(p);
        if (ps != LiveHostSide.unknown) continue;
        final t = _videoTrackFromParticipant(p, preferredSource: preferredSource);
        if (t != null) return t;
      }
    } catch (_) {}

    return null;
  }

  void _toggleViewerAudio() {
    setState(() => _viewerAudioEnabled = !_viewerAudioEnabled);
    _applyViewerAudioSetting();
  }

  void _applyViewerAudioSetting() {
    if (widget.isHost) return;
    final room = _room;
    if (room == null) return;

    final volume = _viewerAudioEnabled ? 1.0 : 0.0;

    try {
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.audioTrackPublications) {
          final track = pub.track;
          if (track == null) continue;
          try {
            (track as dynamic).setVolume(volume);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleFullscreen() async {
    final goingFullscreen = !_isFullscreen;

    if (goingFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }

    if (!mounted) return;
    setState(() => _isFullscreen = goingFullscreen);
  }

  void _toggleViewerLayoutMode() {
    setState(() {
      _viewerLayoutMode = _viewerLayoutMode == _ViewerLayoutMode.single
          ? _ViewerLayoutMode.dual
          : _ViewerLayoutMode.single;
    });
  }

  Future<void> _toggleHostMic() async {
    final room = _room;
    if (room == null) return;

    final next = !_hostMicEnabled;
    try {
      await room.localParticipant?.setMicrophoneEnabled(next);
      if (!mounted) return;
      setState(() => _hostMicEnabled = next);
    } catch (_) {}
  }

  Future<void> _toggleHostCamera() async {
    final room = _room;
    if (room == null) return;

    final next = !_hostCameraEnabled;
    try {
      await room.localParticipant?.setCameraEnabled(next);
      if (!mounted) return;
      setState(() => _hostCameraEnabled = next);
    } catch (_) {}
  }

  Future<void> _toggleHostScreenShare() async {
    await _setHostScreenShareEnabled(!_hostScreenEnabled);
  }

  void _sendQuickToOpponent(String label) {
    final room = _room;
    if (room == null) return;
    if (!_connected) return;
    if (!widget.isHost) return;

    final my = liveHostSideToWire(_mySide).toLowerCase();
    String to = '';
    if (my == 'home') to = 'away';
    if (my == 'away') to = 'home';

    final payload = <String, dynamic>{
      'kind': 'quick',
      'label': label,
      'fromSide': my,
      if (to.isNotEmpty) 'to': to,
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

  @override
  Widget build(BuildContext context) {
    final canSendQuick = widget.isHost && _connected;

    if (!widget.isHost && _isFullscreen) {
      return GlassScaffold(
        appBar: null,
        body: Stack(
          children: [
            Positioned.fill(child: _buildStreamArea(context)),
            if (_incomingQuickText != null)
              Positioned(
                top: 22,
                left: 16,
                right: 16,
                child: _IncomingQuickBanner(
                  text: _incomingQuickText!,
                  from: _incomingQuickFrom,
                ),
              ),
            Positioned(
              top: 16,
              left: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                  onPressed: _toggleFullscreen,
                  tooltip: 'Exit full screen',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          widget.isHost
              ? 'Host Live (Online) • ${widget.matchId}'
              : 'Live (Online) • $_homeLabel vs $_awayLabel',
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Copy match info',
            onPressed: () {
              final txt = 'Match: ${widget.matchId}\nRoom: ${_roomName ?? '(not connected)'}';
              Clipboard.setData(ClipboardData(text: txt));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied match info')),
              );
            },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: isWide
                      ? Row(
                          children: [
                            Expanded(child: _buildStreamArea(context)),
                            const SizedBox(width: 16),
                            SizedBox(width: 360, child: _buildControls(context)),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: _buildStreamArea(context)),
                            const SizedBox(height: 12),
                            _buildControls(context),
                          ],
                        ),
                );
              },
            ),
            if (_incomingQuickText != null)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _IncomingQuickBanner(
                  text: _incomingQuickText!,
                  from: _incomingQuickFrom,
                ),
              ),
            LiveFloatingQuickMessage(
              enabled: canSendQuick,
              messages: _quickMessages,
              onSend: _sendQuickToOpponent,
              icon: Icons.message_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    if (_errorText != null) {
      return Glass(
        borderRadius: 18,
        padding: const EdgeInsets.all(12),
        child: Text(
          'Error: $_errorText',
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (widget.isHost) {
      final started = _connected;

      return Glass(
        borderRadius: 18,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Room: ${_roomName ?? '...'} • side: ${liveHostSideToWire(_mySide)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || started ? null : () => _connectOnline(publishIfHost: true),
                    icon: const Icon(Icons.cast),
                    label: Text(_busy ? 'Starting...' : (started ? 'Broadcasting' : 'Start Broadcast')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await _disconnectRoom();
                            if (mounted) setState(() => _busy = false);
                          },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.filled(
                  onPressed: started ? _toggleHostMic : null,
                  style: IconButton.styleFrom(
                    backgroundColor: (_hostMicEnabled ? Colors.greenAccent : Colors.redAccent).withOpacity(0.3),
                  ),
                  icon: Icon(_hostMicEnabled ? Icons.mic : Icons.mic_off, color: Colors.white),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: started ? _toggleHostCamera : null,
                  style: IconButton.styleFrom(backgroundColor: Colors.white12),
                  icon: Icon(_hostCameraEnabled ? Icons.videocam : Icons.videocam_off, color: Colors.white),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: started ? _toggleHostScreenShare : null,
                  style: IconButton.styleFrom(backgroundColor: Colors.white12),
                  icon: Icon(_hostScreenEnabled ? Icons.screen_share : Icons.stop_screen_share, color: Colors.white),
                  tooltip: _hostScreenEnabled ? 'Stop screen share' : 'Start screen share',
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => BatteryOptimizationGuide.show(context),
              icon: const Icon(Icons.battery_alert_outlined),
              label: const Text('Battery / Background Help'),
            ),
          ],
        ),
      );
    }

    return Glass(
      borderRadius: 18,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filled(
                onPressed: _toggleViewerAudio,
                style: IconButton.styleFrom(
                  backgroundColor: (_viewerAudioEnabled ? Colors.greenAccent : Colors.redAccent).withOpacity(0.3),
                ),
                icon: Icon(_viewerAudioEnabled ? Icons.volume_up : Icons.volume_off, color: Colors.white),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _toggleViewerLayoutMode,
                style: IconButton.styleFrom(backgroundColor: Colors.white12),
                icon: Icon(
                  _viewerLayoutMode == _ViewerLayoutMode.dual ? Icons.view_agenda : Icons.view_week,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _toggleFullscreen,
                style: IconButton.styleFrom(backgroundColor: Colors.white12),
                icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await _disconnectRoom();
                          if (mounted) {
                            setState(() => _busy = false);
                            Navigator.maybePop(context);
                          }
                        },
                  icon: const Icon(Icons.logout),
                  label: const Text('Leave'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_connected)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _connectOnline(publishIfHost: false),
                    icon: const Icon(Icons.refresh),
                    label: Text(_busy ? 'Connecting...' : 'Reconnect'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStreamArea(BuildContext context) {
    // Prefer real LiveKit sources:
    final homeScreen = _remoteVideoForSide(LiveHostSide.home, TrackSource.screenShareVideo);
    final awayScreen = _remoteVideoForSide(LiveHostSide.away, TrackSource.screenShareVideo);

    final homeCam = _remoteVideoForSide(LiveHostSide.home, TrackSource.camera);
    final awayCam = _remoteVideoForSide(LiveHostSide.away, TrackSource.camera);

    final localScreen = _localVideo(TrackSource.screenShareVideo);
    final localCam = _localVideo(TrackSource.camera);

    if (widget.isHost) {
      final mySide = _mySide;
      final main = localScreen ?? localCam ?? (mySide == LiveHostSide.home ? homeScreen : awayScreen);

      final leftTrack = (mySide == LiveHostSide.away) ? homeCam : localCam;
      final rightTrack = (mySide == LiveHostSide.home) ? awayCam : localCam;

      return _GamerStreamLayout(
        matchTitle: '$_homeLabel vs $_awayLabel',
        screenTrack: main,
        camLeft: leftTrack,
        camRight: rightTrack,
        leftLabel: _homeLabel,
        rightLabel: _awayLabel,
        leftHint: (mySide == LiveHostSide.away && leftTrack == null) ? 'Waiting…' : null,
        rightHint: (mySide == LiveHostSide.home && rightTrack == null) ? 'Waiting…' : null,
        primary: _primary,
        onTapLeft: () => setState(() => _primary = _PrimarySide.home),
        onTapRight: () => setState(() => _primary = _PrimarySide.away),
      );
    }

    final primaryScreen = (_primary == _PrimarySide.home)
        ? (homeScreen ?? homeCam)
        : (awayScreen ?? awayCam);

    if (_viewerLayoutMode == _ViewerLayoutMode.single) {
      return _GamerStreamLayout(
        matchTitle: '$_homeLabel vs $_awayLabel',
        screenTrack: primaryScreen,
        camLeft: homeCam,
        camRight: awayCam,
        leftLabel: _homeLabel,
        rightLabel: _awayLabel,
        leftHint: (homeScreen == null && homeCam == null) ? 'Waiting…' : null,
        rightHint: (awayScreen == null && awayCam == null) ? 'Waiting…' : null,
        primary: _primary,
        onTapLeft: () => setState(() => _primary = _PrimarySide.home),
        onTapRight: () => setState(() => _primary = _PrimarySide.away),
      );
    }

    return _DualViewerStreamLayout(
      matchTitle: '$_homeLabel vs $_awayLabel',
      homeMain: homeScreen ?? homeCam,
      awayMain: awayScreen ?? awayCam,
      homeCam: homeCam,
      awayCam: awayCam,
      homeLabel: _homeLabel,
      awayLabel: _awayLabel,
      onTapHome: () {
        setState(() {
          _primary = _PrimarySide.home;
          _viewerLayoutMode = _ViewerLayoutMode.single;
        });
        _toggleFullscreen();
      },
      onTapAway: () {
        setState(() {
          _primary = _PrimarySide.away;
          _viewerLayoutMode = _ViewerLayoutMode.single;
        });
        _toggleFullscreen();
      },
    );
  }
}

class _IncomingQuickBanner extends StatelessWidget {
  const _IncomingQuickBanner({required this.text, this.from});
  final String text;
  final String? from;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Glass(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.cyanAccent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                from == null ? text : '$from: $text',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DualViewerStreamLayout extends StatelessWidget {
  const _DualViewerStreamLayout({
    required this.matchTitle,
    required this.homeMain,
    required this.awayMain,
    required this.homeCam,
    required this.awayCam,
    required this.homeLabel,
    required this.awayLabel,
    required this.onTapHome,
    required this.onTapAway,
  });

  final String matchTitle;

  final VideoTrack? homeMain;
  final VideoTrack? awayMain;
  final VideoTrack? homeCam;
  final VideoTrack? awayCam;

  final String homeLabel;
  final String awayLabel;

  final VoidCallback onTapHome;
  final VoidCallback onTapAway;

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Opacity(
            opacity: 0.9,
            child: Glass(
              borderRadius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                matchTitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onTapHome,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black.withOpacity(0.35),
                        child: homeMain != null
                            ? VideoTrackRenderer(homeMain!)
                            : Center(
                                child: Text(
                                  'Waiting for $homeLabel…',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onTapAway,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.black.withOpacity(0.35),
                        child: awayMain != null
                            ? VideoTrackRenderer(awayMain!)
                            : Center(
                                child: Text(
                                  'Waiting for $awayLabel…',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircularCam(
                label: homeLabel,
                track: homeCam,
                hint: homeCam == null ? 'Cam…' : null,
                selected: false,
                onTap: () {},
              ),
              _CircularCam(
                label: awayLabel,
                track: awayCam,
                hint: awayCam == null ? 'Cam…' : null,
                selected: false,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GamerStreamLayout extends StatelessWidget {
  const _GamerStreamLayout({
    required this.matchTitle,
    required this.screenTrack,
    required this.camLeft,
    required this.camRight,
    required this.leftLabel,
    required this.rightLabel,
    required this.leftHint,
    required this.rightHint,
    required this.primary,
    required this.onTapLeft,
    required this.onTapRight,
  });

  final String matchTitle;

  final VideoTrack? screenTrack;
  final VideoTrack? camLeft;
  final VideoTrack? camRight;

  final String leftLabel;
  final String rightLabel;
  final String? leftHint;
  final String? rightHint;

  final _PrimarySide primary;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(10),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                color: Colors.black.withOpacity(0.35),
                child: screenTrack != null
                    ? VideoTrackRenderer(screenTrack!)
                    : Center(
                        child: Text(
                          'Waiting for stream…',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 92,
            right: 92,
            child: Opacity(
              opacity: 0.9,
              child: Glass(
                borderRadius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(
                  matchTitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: _CircularCam(
              label: leftLabel,
              track: camLeft,
              hint: leftHint,
              selected: primary == _PrimarySide.home,
              onTap: onTapLeft,
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _CircularCam(
              label: rightLabel,
              track: camRight,
              hint: rightHint,
              selected: primary == _PrimarySide.away,
              onTap: onTapRight,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularCam extends StatelessWidget {
  const _CircularCam({
    required this.label,
    required this.track,
    required this.selected,
    required this.onTap,
    this.hint,
  });

  final String label;
  final VideoTrack? track;
  final bool selected;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.86,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.cyanAccent.withOpacity(0.95) : Colors.white24,
                  width: 2,
                ),
                color: Colors.black.withOpacity(0.35),
              ),
              child: ClipOval(
                child: track != null
                    ? VideoTrackRenderer(track!)
                    : Center(
                        child: Text(
                          hint ?? '…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.30),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
