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

  static const _reactions = <String>[
    '👍','😂','🎉','👏','🙏','💯','❤️','💪','👎','👌','🤸','⚽','🏁',
    '🇺🇸','🇬🇧','🇳🇬','🇫🇷','🇩🇪','🇪🇸','🇮🇹','🇧🇷','🇦🇷','🇵🇹','🇲🇽','🇨🇦','🇿🇦','🇯🇵','🇰🇷','🇨🇳','🇮🇳'
  ];

  DocumentReference<Map<String, dynamic>> get _spaceDoc =>
      _firestore.collection('leagues').doc(widget.leagueId).collection('space').doc('current');

  CollectionReference<Map<String, dynamic>> get _reactionsCol =>
      _spaceDoc.collection('reactions');

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

  @override
  void dispose() {
    _spaceSub?.cancel();
    _spaceSub = null;
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

      // Host publishes mic, listener does not
      if (_isHost) {
        await room.localParticipant?.setMicrophoneEnabled(true);
        _micEnabled = true;
      } else {
        await room.localParticipant?.setMicrophoneEnabled(false);
        _micEnabled = false;
      }

      if (!mounted) return;
      setState(() {
        _room = room;
        _connected = true;
        _joiningAudio = false;
      });

      _toast(_isHost ? 'Connected as host' : 'Connected as listener');
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

  Future<void> _toggleMic() async {
    if (_room == null) return;
    if (!_isHost) {
      _toast('Only host mic is enabled for now.');
      return;
    }
    final next = !_micEnabled;
    await _room!.localParticipant?.setMicrophoneEnabled(next);
    if (!mounted) return;
    setState(() => _micEnabled = next);
  }

  Future<void> _sendReaction(String emoji) async {
    if (_uid.isEmpty) return;
    await _reactionsCol.add({
      'emoji': emoji,
      'userId': _uid,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    });
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
                        onPressed: (_connected && _isHost) ? _toggleMic : null,
                        icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                        label: Text(_micEnabled ? 'Mic ON' : 'Mic OFF'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _connected
                      ? (_isHost ? 'Connected as host' : 'Connected as listener')
                      : 'Not connected to audio',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Text('Reactions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _reactions.map((e) {
            return InkWell(
              onTap: () async {
                try {
                  await _sendReaction(e);
                } catch (err) {
                  _toast('Reaction failed: $err');
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(e, style: const TextStyle(fontSize: 18)),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reactionsCol.orderBy('atMs', descending: true).limit(30).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No reactions yet.', style: TextStyle(color: Colors.white38)),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final emoji = (d['emoji'] ?? '').toString();
                  final userId = (d['userId'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    title: Text(emoji, style: const TextStyle(fontSize: 22)),
                    subtitle: Text(userId, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
