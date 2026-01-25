import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../models/league_space.dart';
import '../services/livekit_service.dart';

class LeagueSpaceRoomScreen extends StatefulWidget {
  final String leagueId;

  const LeagueSpaceRoomScreen({
    super.key,
    required this.leagueId,
  });

  @override
  State<LeagueSpaceRoomScreen> createState() => _LeagueSpaceRoomScreenState();
}

class _LeagueSpaceRoomScreenState extends State<LeagueSpaceRoomScreen> {
  final _firestore = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _spaceSub;
  LeagueSpace? _space;

  bool _loading = true;
  String _error = '';

  String _uid = '';

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _joiningAudio = false;
  bool _connected = false;
  bool _micEnabled = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mySpeakerSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myRequestSub;

  bool _isSpeakerApproved = false;
  bool _speakerMutedByHost = false;
  String _myRequestStatus = ''; 

  static const _reactions = <String>[
    '👍','😂','🎉','👏','🙏','💯','❤️','💪','👎','👌','🤸','⚽','🏁',
    '🇺🇸','🇬🇧','🇳🇬','🇫🇷','🇩🇪','🇪🇸','🇮🇹','🇧🇷','🇦🇷','🇵🇹','🇲🇽','🇨🇦','🇿🇦','🇯🇵','🇰🇷','🇨🇳','🇮🇳'
  ];

  DocumentReference<Map<String, dynamic>> get _spaceDoc =>
      _firestore.collection('leagues').doc(widget.leagueId).collection('space').doc('current');

  CollectionReference<Map<String, dynamic>> get _reactionsCol => _spaceDoc.collection('reactions');
  CollectionReference<Map<String, dynamic>> get _requestsCol => _spaceDoc.collection('requests');
  CollectionReference<Map<String, dynamic>> get _speakersCol => _spaceDoc.collection('speakers');

  DocumentReference<Map<String, dynamic>> get _myRequestDoc => _requestsCol.doc(_uid);
  DocumentReference<Map<String, dynamic>> get _mySpeakerDoc => _speakersCol.doc(_uid);

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
      if (!mounted) return;
      if (!snap.exists) {
        setState(() { _space = null; _loading = false; });
        return;
      }
      try {
        final space = LeagueSpace.fromJson(snap.data()!);
        setState(() { _space = space; _loading = false; });
        _ensureSpaceRoleListeners();
      } catch (e) {
        setState(() { _loading = false; _error = 'Parse error: $e'; });
      }
    });
  }

  void _ensureSpaceRoleListeners() {
    if (_uid.isEmpty || _space == null) return;

    if (_isHost) {
      if (!_isSpeakerApproved) {
        setState(() { _isSpeakerApproved = true; _speakerMutedByHost = false; });
      }
      return;
    }

    _mySpeakerSub ??= _mySpeakerDoc.snapshots().listen((snap) async {
      final approved = snap.exists;
      final muted = (snap.data()?['muted'] == true);
      
      if (!mounted) return;
      
      final wasApproved = _isSpeakerApproved;
      setState(() {
        _isSpeakerApproved = approved;
        _speakerMutedByHost = muted;
      });

      // ✅ FIX: Aggressive Safe Flow to ensure Mic Opens
      if (_connected && _room != null) {
        if (!approved || muted) {
          if (_micEnabled) {
            await _room?.localParticipant?.setMicrophoneEnabled(false);
            if (mounted) setState(() => _micEnabled = false);
          }
        } else if (approved && !wasApproved) {
          _toast('Activating speaker permissions...');
          try {
            // 1. Trigger Backend to update LiveKit Server permissions
            await LiveKitService.approveSpeaker(
              leagueId: widget.leagueId,
              targetUserId: _uid,
            );

            // 2. Wait longer (800ms) for the LiveKit Server to process the update
            await Future.delayed(const Duration(milliseconds: 800));

            // 3. Request hardware mic enable
            await _room?.localParticipant?.setMicrophoneEnabled(true);
            
            if (mounted) setState(() => _micEnabled = true);
            _toast('Mic is now LIVE');
          } catch (e) {
            _toast('Error opening mic: $e');
          }
        }
      }
    });

    _myRequestSub ??= _myRequestDoc.snapshots().listen((snap) {
      if (mounted) setState(() => _myRequestStatus = snap.data()?['status'] ?? '');
    });
  }

  @override
  void dispose() {
    _spaceSub?.cancel();
    _mySpeakerSub?.cancel();
    _myRequestSub?.cancel();
    _disconnectAudio();
    super.dispose();
  }

  bool get _isLive => _space?.isLive == true;
  bool get _isHost => _space != null && _uid.isNotEmpty && _space!.hostUserId == _uid;

  Future<void> _connectAudio() async {
    if (_joiningAudio || _connected) return;
    setState(() { _joiningAudio = true; _error = ''; });

    try {
      final token = await LiveKitService.fetchToken(
        leagueId: widget.leagueId,
        userId: _uid,
        isHost: _isHost,
      );

      final room = Room();
      _listener = room.createListener();
      
      _listener!.on<RoomConnectedEvent>((_) => setState(() => _connected = true));
      _listener!.on<RoomDisconnectedEvent>((_) => setState(() { _connected = false; _micEnabled = false; }));

      await room.connect(token.url, token.token);

      if (_isHost) {
        await room.localParticipant?.setMicrophoneEnabled(true);
        _micEnabled = true;
      } else if (_isSpeakerApproved && !_speakerMutedByHost) {
        await LiveKitService.approveSpeaker(leagueId: widget.leagueId, targetUserId: _uid);
        await Future.delayed(const Duration(milliseconds: 500));
        await room.localParticipant?.setMicrophoneEnabled(true);
        _micEnabled = true;
      }

      setState(() { _room = room; _joiningAudio = false; });
    } catch (e) {
      setState(() { _joiningAudio = false; _error = 'Connect error: $e'; });
    }
  }

  Future<void> _disconnectAudio() async {
    _listener?.dispose();
    await _room?.disconnect();
    _room = null;
    setState(() { _connected = false; _micEnabled = false; });
  }

  Future<void> _toggleMic() async {
    if (_room == null || !_isSpeakerApproved || _speakerMutedByHost) return;
    final next = !_micEnabled;
    await _room?.localParticipant?.setMicrophoneEnabled(next);
    setState(() => _micEnabled = next);
  }

  Future<void> _requestToSpeak() async {
    await _myRequestDoc.set({
      'userId': _uid,
      'status': 'pending',
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
  }

  Future<void> _withdrawRequest() async => await _myRequestDoc.delete();

  Future<void> _sendReaction(String emoji) async {
    await _reactionsCol.add({
      'emoji': emoji,
      'userId': _uid,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _approveRequest(String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = _firestore.batch();
    batch.set(_speakersCol.doc(userId), {'userId': userId, 'muted': false, 'approvedAtMs': now});
    batch.set(_requestsCol.doc(userId), {'status': 'approved'}, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> _denyRequest(String userId) async {
    await _requestsCol.doc(userId).set({'status': 'denied'}, SetOptions(merge: true));
  }

  Future<void> _removeSpeaker(String userId) async {
    await _speakersCol.doc(userId).delete();
  }

  Future<void> _toggleMuteSpeaker(String userId, bool muted) async {
    await _speakersCol.doc(userId).update({'muted': muted});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: AppBar(
        title: const Text('League Space'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => SyncTrigger.trySync(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator()) 
        : _buildRoom(context),
    );
  }

  Widget _buildRoom(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Glass(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    title: Text(_space?.title ?? 'League Space', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: Text(_isLive ? 'LIVE' : 'ENDED', style: TextStyle(color: _isLive ? Colors.cyanAccent : Colors.white38)),
                    trailing: _isLive ? const Icon(Icons.graphic_eq, color: Colors.cyanAccent) : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _joiningAudio ? null : (_connected ? _disconnectAudio : _connectAudio),
                          icon: _joiningAudio ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_connected ? Icons.call_end : Icons.headset),
                          label: Text(_connected ? 'Leave Space' : 'Join Audio'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        iconSize: 32,
                        icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off, color: _micEnabled ? Colors.cyanAccent : Colors.white54),
                        onPressed: (_connected && _isSpeakerApproved && !_speakerMutedByHost) ? _toggleMic : null,
                      ),
                    ],
                  ),
                  if (!_isHost && !_isSpeakerApproved) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white10),
                      onPressed: _myRequestStatus == 'pending' ? _withdrawRequest : _requestToSpeak,
                      child: Text(_myRequestStatus == 'pending' ? 'Cancel Request' : 'Request to Speak'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isHost) _buildHostPanel(),
            const Text('Reactions', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reactions.map((e) => InkWell(
                onTap: () => _sendReaction(e),
                child: Glass(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 20))),
              )).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Recent Reactions', style: TextStyle(color: Colors.white70, fontSize: 12)),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _reactionsCol.orderBy('atMs', descending: true).limit(5).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox();
                return Column(
                  children: snap.data!.docs.map((d) => ListTile(
                    dense: true,
                    leading: Text(d.data()['emoji'] ?? ''),
                    title: Text(d.data()['userId'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Host Control Panel', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _requestsCol.where('status', isEqualTo: 'pending').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData || snap.data!.docs.isEmpty) return const Text('No pending requests', style: TextStyle(color: Colors.white24, fontSize: 12));
            return Column(
              children: snap.data!.docs.map((d) => Glass(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(d.id, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: () => _denyRequest(d.id)),
                      IconButton(icon: const Icon(Icons.check, color: Colors.greenAccent), onPressed: () => _approveRequest(d.id)),
                    ],
                  ),
                ),
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
