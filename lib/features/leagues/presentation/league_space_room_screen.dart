import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../models/league_space.dart';
import '../services/livekit_service.dart';

class LeagueSpaceRoomScreen extends StatefulWidget {
  final String leagueId;
  const LeagueSpaceRoomScreen({super.key, required this.leagueId});

  @override
  State<LeagueSpaceRoomScreen> createState() => _LeagueSpaceRoomScreenState();
}

class _LeagueSpaceRoomScreenState extends State<LeagueSpaceRoomScreen> {
  final _firestore = FirebaseFirestore.instance;
  StreamSubscription? _spaceSub;
  StreamSubscription? _mySpeakerSub;
  StreamSubscription? _myRequestSub;

  LeagueSpace? _space;
  bool _loading = true;
  String _error = '';
  String _uid = '';

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _joiningAudio = false;
  bool _connected = false;
  bool _micEnabled = false;
  bool _isSpeakerApproved = false;
  bool _speakerMutedByHost = false;
  String _myRequestStatus = '';

  DocumentReference<Map<String, dynamic>> get _spaceDoc =>
      _firestore.collection('leagues').doc(widget.leagueId).collection('space').doc('current');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await SyncTrigger.trySync();
    final prefs = await PreferencesService.create();
    _uid = prefs.getCurrentUserId() ?? '';

    _spaceSub = _spaceDoc.snapshots().listen((snap) {
      if (!mounted || !snap.exists) return;
      setState(() {
        _space = LeagueSpace.fromJson(snap.data()!);
        _loading = false;
      });
      _ensureSpaceRoleListeners();
    });
  }

  void _ensureSpaceRoleListeners() {
    if (_uid.isEmpty || _space == null) return;

    if (_uid == _space!.hostUserId) {
      setState(() { _isSpeakerApproved = true; _speakerMutedByHost = false; });
      return;
    }

    _mySpeakerSub ??= _spaceDoc.collection('speakers').doc(_uid).snapshots().listen((snap) async {
      final approved = snap.exists;
      final muted = (snap.data()?['muted'] == true);
      final wasApproved = _isSpeakerApproved;

      if (!mounted) return;
      setState(() {
        _isSpeakerApproved = approved;
        _speakerMutedByHost = muted;
      });

      // If just approved, trigger the mic flow
      if (approved && !wasApproved && _connected) {
        _handleNewSpeakerActivation();
      }
    });

    _myRequestSub ??= _spaceDoc.collection('requests').doc(_uid).snapshots().listen((snap) {
      if (mounted) setState(() => _myRequestStatus = snap.data()?['status'] ?? '');
    });
  }

  Future<void> _handleNewSpeakerActivation() async {
    _toast('Activating Microphone...');
    
    // 1. Tell Server to update LiveKit permissions
    try {
      await LiveKitService.approveSpeaker(leagueId: widget.leagueId, targetUserId: _uid);
    } catch (e) {
      print('ApproveSpeaker Service Error: $e');
    }

    // 2. Wait for server to sync (Max 4 seconds)
    bool ready = false;
    for (int i = 0; i < 8; i++) {
      if (_room?.localParticipant?.permissions?.canPublish == true) {
        ready = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 3. Force Reconnect if still not ready (This fixes the "Waiting" bug)
    if (!ready && _connected) {
      _toast('Syncing with server...');
      await _disconnectAudio();
      await _connectAudio();
      return;
    }

    // 4. Final attempt to open mic
    if (ready) {
      await _enableMicHardware();
    }
  }

  Future<void> _enableMicHardware() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      try {
        await _room?.localParticipant?.setMicrophoneEnabled(true);
        if (mounted) setState(() => _micEnabled = true);
      } catch (e) {
        _toast('Mic failed. Try toggling the button.');
      }
    }
  }

  Future<void> _connectAudio() async {
    if (_joiningAudio || _connected) return;
    setState(() => _joiningAudio = true);

    try {
      final token = await LiveKitService.fetchToken(
        leagueId: widget.leagueId,
        userId: _uid,
        isHost: _uid == _space?.hostUserId,
      );

      _room = Room();
      _listener = _room!.createListener();
      
      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted) setState(() { _connected = false; _micEnabled = false; });
      });

      await _room!.connect(token.url, token.token);
      
      if (mounted) {
        setState(() { _connected = true; _joiningAudio = false; });
        if (_uid == _space?.hostUserId || (_isSpeakerApproved && !_speakerMutedByHost)) {
          _enableMicHardware();
        }
      }
    } catch (e) {
      if (mounted) setState(() { _joiningAudio = false; _error = 'Connect Error: $e'; });
    }
  }

  Future<void> _disconnectAudio() async {
    await _listener?.dispose();
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
    if (mounted) setState(() => _connected = false);
  }

  Future<void> _toggleMic() async {
    if (!_connected || _speakerMutedByHost || !_isSpeakerApproved) return;
    final next = !_micEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(next);
    setState(() => _micEnabled = next);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  void dispose() {
    _spaceSub?.cancel();
    _mySpeakerSub?.cancel();
    _myRequestSub?.cancel();
    _disconnectAudio();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // UI logic (simplified for brevity, keeping your existing layout style)
    return GlassScaffold(
      appBar: AppBar(title: const Text('League Space'), backgroundColor: Colors.transparent),
      body: _loading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              Text(_space?.title ?? 'Space'),
              const SizedBox(height: 20),
              if (!_connected) 
                ElevatedButton(onPressed: _connectAudio, child: const Text('Join Audio'))
              else ...[
                ElevatedButton(onPressed: _disconnectAudio, child: const Text('Leave')),
                IconButton(
                  icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                  onPressed: _isSpeakerApproved ? _toggleMic : null,
                ),
              ],
              if (!_isSpeakerApproved && _myRequestStatus != 'pending')
                ElevatedButton(onPressed: () => _spaceDoc.collection('requests').doc(_uid).set({'status': 'pending', 'userId': _uid}), child: const Text('Request to Speak'))
            ],
          ),
    );
  }
}
