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
  String _myRequestStatus = ''; // '', 'pending', 'approved', 'denied'

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
        setState(() {
          _space = null;
          _loading = false;
          _error = '';
        });
        return;
      }

      try {
        final data = snap.data() ?? <String, dynamic>{};
        final space = LeagueSpace.fromJson(data);

        setState(() {
          _space = space;
          _loading = false;
          _error = '';
        });

        // once we have uid + a space doc, attach speaker/request listeners
        _ensureSpaceRoleListeners();
      } catch (e) {
        setState(() {
          _loading = false;
          _error = 'Failed to parse space: $e';
        });
      }
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Space stream error: $e';
      });
    });
  }

  void _ensureSpaceRoleListeners() {
    if (_uid.isEmpty) return;
    if (_space == null) return;

    // Host is always "speaker-approved" from the UI perspective.
    if (_isHost) {
      if (!_isSpeakerApproved || _speakerMutedByHost) {
        setState(() {
          _isSpeakerApproved = true;
          _speakerMutedByHost = false;
          _myRequestStatus = '';
        });
      }
      return;
    }

    _mySpeakerSub ??= _mySpeakerDoc.snapshots().listen((snap) async {
      final approved = snap.exists;
      final muted = (snap.data()?['muted'] == true);

      final wasApproved = _isSpeakerApproved;
      final prevMuted = _speakerMutedByHost;

      if (!mounted) return;
      setState(() {
        _isSpeakerApproved = approved;
        _speakerMutedByHost = muted;
      });

      // ✅ SAFE FLOW: Handling Mic Activation
      if (_connected && _room != null) {
        if (!approved || muted) {
          if (_micEnabled) {
            await _room?.localParticipant?.setMicrophoneEnabled(false);
            if (mounted) setState(() => _micEnabled = false);
          }
        } else if (approved && !wasApproved) {
          // User was just approved!
          _toast('Syncing speaker permissions...');
          try {
            // 1️⃣ Update LiveKit server permissions via Cloudflare Worker
            await LiveKitService.approveSpeaker(
              leagueId: widget.leagueId,
              targetUserId: _uid,
            );

            // 2️⃣ Wait for permission propagation (Smart Poll)
            bool canPublish = false;
            for (int i = 0; i < 10; i++) { // Try for 5 seconds
              if (_room?.localParticipant?.permissions?.canPublish == true) {
                canPublish = true;
                break;
              }
              await Future.delayed(const Duration(milliseconds: 500));
            }
            
            if (!canPublish) {
              _toast('Server permission pending... retrying mic.');
            }

            // 3️⃣ Enable mic hardware safely with PERMISSION CHECK
            var status = await Permission.microphone.request();
            if (status.isGranted) {
               try {
                  await _room?.localParticipant?.setMicrophoneEnabled(true);
                  if (mounted) {
                    setState(() => _micEnabled = true);
                    _toast('Mic enabled!');
                  }
               } catch (publishError) {
                  // Catch TrackPublishException explicitly
                  _toast('Mic not ready yet. Please toggle mic button.');
                  print('Publish error: $publishError');
               }
            } else {
              _toast('Mic permission denied. Please enable in settings.');
              openAppSettings();
            }
          } catch (e) {
            _toast('Mic sync failed: $e');
          }
        }
      }

      // Friendly toast on state transitions
      if (wasApproved != approved && approved) _toast('You are now a speaker.');
      if (wasApproved != approved && !approved) _toast('You are now a listener.');
      if (prevMuted != muted && muted) _toast('Host muted you.');
      if (prevMuted != muted && !muted && approved) _toast('Host unmuted you.');
    });

    _myRequestSub ??= _myRequestDoc.snapshots().listen((snap) {
      if (!mounted) return;
      if (!snap.exists) {
        setState(() => _myRequestStatus = '');
        return;
      }
      final status = (snap.data()?['status'] ?? '').toString();
      setState(() => _myRequestStatus = status);
    });
  }

  @override
  void dispose() {
    _spaceSub?.cancel();
    _spaceSub = null;

    _mySpeakerSub?.cancel();
    _mySpeakerSub = null;

    _myRequestSub?.cancel();
    _myRequestSub = null;

    _disconnectAudio();
    super.dispose();
  }

  bool get _isLive => _space?.isLive == true;
  bool get _isHost => _space != null && _uid.isNotEmpty && _space!.hostUserId == _uid;

  Future<void> _connectAudio() async {
    if (_joiningAudio || _connected) return;
    if (!_isLive) {
      _toast('Space is not live.');
      return;
    }
    if (_uid.isEmpty) {
      _toast('No user id available.');
      return;
    }

    // 🔴 CRITICAL: Request microphone permission before connection logic
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      _toast('Microphone permission is required to join audio.');
      return;
    }

    setState(() {
      _joiningAudio = true;
      _error = '';
    });

    try {
      final token = await LiveKitService.fetchToken(
        leagueId: widget.leagueId,
        userId: _uid,
        isHost: _isHost,
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

      _listener!.on<RoomConnectedEvent>((event) {
        if (!mounted) return;
        setState(() {
          _connected = true;
        });
      });
      
      _listener!.on<ParticipantPermissionsUpdatedEvent>((event) {
         // This helps us know when we can actually publish
         if (event.participant == room.localParticipant) {
           print('Permissions updated: canPublish=${event.permissions.canPublish}');
         }
      });

      _listener!.on<RoomDisconnectedEvent>((event) {
        if (!mounted) return;
        setState(() {
          _connected = false;
          _micEnabled = false;
        });
      });

      await room.connect(
        token.url,
        token.token,
      );

      // Mic policy on join:
      if (_isHost) {
        await room.localParticipant?.setMicrophoneEnabled(true);
        _micEnabled = true;
      } else {
        final shouldEnable = _isSpeakerApproved && !_speakerMutedByHost;
        if (shouldEnable) {
          try {
            await LiveKitService.approveSpeaker(leagueId: widget.leagueId, targetUserId: _uid);
            
            // Wait loop for permission
            for (int i=0; i<6; i++) {
              if (room.localParticipant?.permissions?.canPublish == true) break;
              await Future.delayed(const Duration(milliseconds: 500));
            }
            
            if (await Permission.microphone.isGranted) {
               await room.localParticipant?.setMicrophoneEnabled(true);
               _micEnabled = true;
            }
          } catch (_) {
             _micEnabled = false;
          }
        } else {
          _micEnabled = false;
        }
      }

      if (!mounted) return;
      setState(() {
        _room = room;
        _connected = true;
        _joiningAudio = false;
      });

      _toast(_isHost ? 'Connected as host' : 'Connected to audio');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joiningAudio = false;
        _error = 'Audio connect failed: $e';
      });
    }
  }

  Future<void> _disconnectAudio() async {
    try {
      _listener?.dispose();
      _listener = null;
      await _room?.disconnect();
      await _room?.dispose();
    } catch (_) {}
    _room = null;
    _connected = false;
    _micEnabled = false;
  }

  bool get _canToggleMic {
    if (_room == null || !_connected) return false;
    if (_isHost) return true;
    if (!_isSpeakerApproved) return false;
    if (_speakerMutedByHost) return false;
    return true;
  }

  Future<void> _toggleMic() async {
    if (_room == null) return;

    if (!_canToggleMic) {
      if (_isHost) {
        _toast('Mic unavailable.');
      } else if (_speakerMutedByHost) {
        _toast('You are muted by the host.');
      } else if (!_isSpeakerApproved) {
        _toast('Request to speak to enable your mic.');
      }
      return;
    }

    final next = !_micEnabled;
    
    // Explicit permission check on toggle
    if (next) {
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
        if (!status.isGranted) {
           _toast('Mic permission denied.');
           return;
        }
      }
      
      // Check server permissions before trying to publish
      if (_room?.localParticipant?.permissions?.canPublish == false) {
         _toast('Waiting for server permission...');
         await LiveKitService.approveSpeaker(leagueId: widget.leagueId, targetUserId: _uid);
         await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    try {
      await _room?.localParticipant?.setMicrophoneEnabled(next);
      if (!mounted) return;
      setState(() => _micEnabled = next);
    } catch (e) {
      _toast('Failed to toggle mic: $e');
      // If we failed with TrackPublishException, permissions might still be syncing
    }
  }

  Future<void> _requestToSpeak() async {
    if (_uid.isEmpty) return;
    if (_space == null) return;
    if (_isHost) return;
    if (!_isLive) {
      _toast('Space is not live.');
      return;
    }

    try {
      await _myRequestDoc.set({
        'userId': _uid,
        'status': 'pending',
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      _toast('Request sent.');
    } catch (e) {
      _toast('Request failed: $e');
    }
  }

  Future<void> _withdrawRequest() async {
    if (_uid.isEmpty) return;
    try {
      await _myRequestDoc.delete();
      _toast('Request removed.');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  Future<void> _sendReaction(String emoji) async {
    if (_uid.isEmpty) return;
    await _reactionsCol.add({
      'emoji': emoji,
      'userId': _uid,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _approveRequest(String userId) async {
    if (!_isHost) return;

    final batch = _firestore.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    batch.set(_speakersCol.doc(userId), {
      'userId': userId,
      'approvedBy': _uid,
      'approvedAtMs': now,
      'muted': false,
    }, SetOptions(merge: true));

    batch.set(_requestsCol.doc(userId), {
      'userId': userId,
      'status': 'approved',
      'updatedAtMs': now,
    }, SetOptions(merge: true));

    await batch.commit();
    _toast('Approved $userId');
  }

  Future<void> _denyRequest(String userId) async {
    if (!_isHost) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    await _requestsCol.doc(userId).set({
      'userId': userId,
      'status': 'denied',
      'updatedAtMs': now,
    }, SetOptions(merge: true));

    // ensure not speaker
    await _speakersCol.doc(userId).delete().catchError((_) {});
    _toast('Denied $userId');
  }

  Future<void> _removeSpeaker(String userId) async {
    if (!_isHost) return;
    await _speakersCol.doc(userId).delete();
    _toast('Removed speaker $userId');
  }

  Future<void> _toggleMuteSpeaker(String userId, bool muted) async {
    if (!_isHost) return;
    await _speakersCol.doc(userId).set({'muted': muted}, SetOptions(merge: true));
    _toast(muted ? 'Muted $userId' : 'Unmuted $userId');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
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
            tooltip: 'Sync',
            onPressed: () async {
              await SyncTrigger.trySync();
              _toast('Synced');
            },
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Glass(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                    : _error.isNotEmpty
                        ? Center(
                            child: Text(
                              _error,
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _space == null
                            ? const Center(
                                child: Text(
                                  'No active space right now.\nAsk the organizer to start one.',
                                  style: TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                              )
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              _isLive ? Icons.graphic_eq : Icons.spatial_audio_off,
              color: _isLive ? Colors.cyanAccent : Colors.white38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                space.title ?? 'League Space',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: _isLive ? Colors.redAccent.withOpacity(0.20) : Colors.white10,
                border: Border.all(color: _isLive ? Colors.redAccent.withOpacity(0.6) : Colors.white24),
              ),
              child: Text(
                _isLive ? 'LIVE' : 'ENDED',
                style: TextStyle(
                  color: _isLive ? Colors.redAccent : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Host: ${space.hostUserId}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 16),

        Glass(
          borderRadius: 16,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _joiningAudio
                            ? null
                            : _connected
                                ? () async {
                                    await _disconnectAudio();
                                    if (!mounted) return;
                                    setState(() {});
                                  }
                                : _connectAudio,
                        icon: _joiningAudio
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_connected ? Icons.call_end : Icons.headset),
                        label: Text(_connected ? 'Leave Audio' : 'Join Audio'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _canToggleMic ? _toggleMic : null,
                        icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                        label: Text(_micEnabled ? 'Mic ON' : 'Mic OFF'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _connected
                      ? (_isHost
                          ? 'Connected as host'
                          : (_isSpeakerApproved
                              ? (_speakerMutedByHost ? 'Connected as speaker (muted)' : 'Connected as speaker')
                              : 'Connected as listener'))
                      : 'Not connected to audio',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),

                // Listener UI: request-to-speak controls
                if (!_isHost) ...[
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_isLive && !_isSpeakerApproved && _myRequestStatus != 'pending')
                              ? _requestToSpeak
                              : null,
                          icon: const Icon(Icons.record_voice_over),
                          label: Text(
                            _isSpeakerApproved
                                ? 'You are a speaker'
                                : (_myRequestStatus == 'pending' ? 'Request Pending' : 'Request to Speak'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: (_myRequestStatus == 'pending') ? _withdrawRequest : null,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_myRequestStatus == 'denied')
                    const Text(
                      'Request denied.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Host panel: approve/deny + speaker controls
        if (_isHost) ...[
          Glass(
            borderRadius: 16,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Host Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  const Text('Requests', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _requestsCol.where('status', isEqualTo: 'pending').snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Text(
                          'Requests error: ${snap.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Text('No pending requests.', style: TextStyle(color: Colors.white38));
                      }
                      return Column(
                        children: docs.map((doc) {
                          final d = doc.data();
                          final userId = (d['userId'] ?? doc.id).toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(userId, style: const TextStyle(color: Colors.white)),
                              subtitle: const Text('wants to speak', style: TextStyle(color: Colors.white54, fontSize: 12)),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _denyRequest(userId);
                                      } catch (e) {
                                        _toast('Deny failed: $e');
                                      }
                                    },
                                    child: const Text('Deny'),
                                  ),
                                  FilledButton(
                                    onPressed: () async {
                                      try {
                                        await _approveRequest(userId);
                                      } catch (e) {
                                        _toast('Approve failed: $e');
                                      }
                                    },
                                    child: const Text('Approve'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 12),
                  const Text('Speakers', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _speakersCol.orderBy('approvedAtMs', descending: false).snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Text(
                          'Speakers error: ${snap.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Text('No speakers yet.', style: TextStyle(color: Colors.white38));
                      }
                      return Column(
                        children: docs.map((doc) {
                          final d = doc.data();
                          final userId = (d['userId'] ?? doc.id).toString();
                          final muted = d['muted'] == true;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(userId, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                muted ? 'Muted' : 'Unmuted',
                                style: TextStyle(color: muted ? Colors.orangeAccent : Colors.white54, fontSize: 12),
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _toggleMuteSpeaker(userId, !muted);
                                      } catch (e) {
                                        _toast('Mute failed: $e');
                                      }
                                    },
                                    child: Text(muted ? 'Unmute' : 'Mute'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _removeSpeaker(userId);
                                      } catch (e) {
                                        _toast('Remove failed: $e');
                                      }
                                    },
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
