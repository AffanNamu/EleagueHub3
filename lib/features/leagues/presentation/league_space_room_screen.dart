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

  // ---- Spaces (requests/speakers) state ----
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
        final data = snap.data() ?? <String, dynamic>{};
        _space = LeagueSpace.fromJson(data);
        setState(() { _loading = false; });
        _ensureSpaceRoleListeners();
      } catch (e) {
        setState(() { _loading = false; _error = 'Parse error: $e'; });
      }
    });
  }

  void _ensureSpaceRoleListeners() {
    if (_uid.isEmpty || _space == null) return;

    if (_isHost) {
      setState(() { _isSpeakerApproved = true; _speakerMutedByHost = false; });
      return;
    }

    _mySpeakerSub ??= _speakersCol.doc(_uid).snapshots().listen((snap) async {
      final approved = snap.exists;
      final muted = (snap.data()?['muted'] == true);
      final wasApproved = _isSpeakerApproved;

      if (!mounted) return;
      setState(() {
        _isSpeakerApproved = approved;
        _speakerMutedByHost = muted;
      });

      // Handle transitions
      if (_connected && _room != null) {
        if (!approved || muted) {
          if (_micEnabled) _toggleMic(forceOff: true);
        } else if (approved && !wasApproved) {
          _handleSpeakerActivationFlow();
        }
      }
    });

    _myRequestSub ??= _requestsCol.doc(_uid).snapshots().listen((snap) {
      if (mounted) setState(() => _myRequestStatus = snap.data()?['status'] ?? '');
    });
  }

  /// CRITICAL FIX: The logic to handle moving from Listener to Speaker
  Future<void> _handleSpeakerActivationFlow() async {
    _toast('Syncing speaker permissions...');
    
    try {
      // 1. Tell backend to update LiveKit server
      await LiveKitService.approveSpeaker(leagueId: widget.leagueId, targetUserId: _uid);
      
      // 2. Check if we already have permission
      if (_room?.localParticipant?.permissions?.canPublish == true) {
        await _enableMicSafely();
        return;
      }

      // 3. Wait for the server update (Max 3 seconds)
      bool ready = false;
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_room?.localParticipant?.permissions?.canPublish == true) {
          ready = true;
          break;
        }
      }

      if (ready) {
        await _enableMicSafely();
      } else {
        // 4. Force Reconnect (Nuclear option) - gets a fresh token with permissions
        _toast('Server slow. Refreshing connection...');
        await _disconnectAudio();
        await _connectAudio();
      }
    } catch (e) {
      _toast('Mic sync failed. Try reconnecting.');
    }
  }

  Future<void> _enableMicSafely() async {
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      try {
        await _room?.localParticipant?.setMicrophoneEnabled(true);
        if (mounted) setState(() => _micEnabled = true);
        _toast('Mic active!');
      } catch (e) {
        _toast('Could not open mic hardware.');
      }
    } else {
      _toast('Mic permission required.');
    }
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
    if (!_isLive) return _toast('Space is not live.');

    setState(() { _joiningAudio = true; _error = ''; });

    try {
      final token = await LiveKitService.fetchToken(
        leagueId: widget.leagueId,
        userId: _uid,
        isHost: _isHost,
      );

      _room = Room();
      _listener = _room!.createListener();

      _listener!.on<RoomConnectedEvent>((_) => setState(() => _connected = true));
      _listener!.on<RoomDisconnectedEvent>((_) => setState(() { _connected = false; _micEnabled = false; }));
      
      // React immediately if permissions change while connected
      _listener!.on<ParticipantPermissionsUpdatedEvent>((event) {
        if (event.participant == _room?.localParticipant && event.permissions.canPublish) {
          if (_isSpeakerApproved && !_speakerMutedByHost && !_micEnabled) {
            _enableMicSafely();
          }
        }
      });

      await _room!.connect(token.url, token.token);

      if (_isHost || (_isSpeakerApproved && !_speakerMutedByHost)) {
        await _enableMicSafely();
      }

      if (mounted) setState(() { _connected = true; _joiningAudio = false; });
    } catch (e) {
      if (mounted) setState(() { _joiningAudio = false; _error = 'Connect Error: $e'; });
    }
  }

  Future<void> _disconnectAudio() async {
    _listener?.dispose();
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
    if (mounted) setState(() { _connected = false; _micEnabled = false; });
  }

  Future<void> _toggleMic({bool? forceOff}) async {
    if (_room == null || !_connected) return;
    bool next = forceOff == true ? false : !_micEnabled;
    
    if (next && _room?.localParticipant?.permissions?.canPublish == false) {
      _toast('Waiting for server permission...');
      return;
    }

    try {
      await _room?.localParticipant?.setMicrophoneEnabled(next);
      if (mounted) setState(() => _micEnabled = next);
    } catch (e) {
      _toast('Mic error: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: AppBar(title: const Text('League Space'), backgroundColor: Colors.transparent),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Glass(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildRoom(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoom(BuildContext context) {
    final space = _space!;
    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.graphic_eq, color: _isLive ? Colors.cyanAccent : Colors.white38),
            const SizedBox(width: 10),
            Expanded(child: Text(space.title ?? 'Space', style: const TextStyle(fontWeight: FontWeight.bold))),
            Text(_isLive ? 'LIVE' : 'ENDED', style: TextStyle(color: _isLive ? Colors.red : Colors.grey)),
          ],
        ),
        const SizedBox(height: 20),
        
        // Audio Controls
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _joiningAudio ? null : (_connected ? _disconnectAudio : _connectAudio),
                icon: Icon(_connected ? Icons.call_end : Icons.headset),
                label: Text(_connected ? 'Leave' : 'Join Audio'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_connected && _isSpeakerApproved) ? () => _toggleMic() : null,
                icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                label: Text(_micEnabled ? 'On' : 'Off'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        if (!_isHost) ...[
          if (!_isSpeakerApproved)
            ElevatedButton(
              onPressed: _myRequestStatus == 'pending' 
                  ? null 
                  : () => _requestsCol.doc(_uid).set({'userId': _uid, 'status': 'pending'}),
              child: Text(_myRequestStatus == 'pending' ? 'Request Pending' : 'Request to Speak'),
            ),
        ],

        // Host Panel
        if (_isHost) ...[
          const Divider(height: 40),
          const Text('Manage Requests', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _requestsCol.where('status', isEqualTo: 'pending').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox();
                return ListView(
                  children: snap.data!.docs.map((doc) {
                    final uid = doc.id;
                    return ListTile(
                      title: Text(uid),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _approveUser(uid)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => doc.reference.delete()),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _approveUser(String userId) async {
    await _speakersCol.doc(userId).set({'userId': userId, 'muted': false});
    await _requestsCol.doc(userId).update({'status': 'approved'});
  }
}
