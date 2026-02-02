import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
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
  final UserProfileRepository _profiles = UserProfileRepository();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _spaceSub;
  LeagueSpace? _space;

  bool _loading = true;
  String _error = '';

  String _uid = '';

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  bool _joiningAudio = false;
  bool _connected = false;

  /// True iff the local mic is currently unmuted (sending).
  bool _micEnabled = false;

  /// True iff we have already caused LiveKit to create+publish the mic track once for this join.
  /// This is the key Twitter-Spaces behavior: approval only unmutes an already-published track.
  bool _micPrimed = false;

  bool _requestedMicPermissionOnJoin = false;

  // ---- Spaces (requests/speakers) state ----
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mySpeakerSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myRequestSub;

  bool _isSpeakerApproved = false;
  bool _speakerMutedByHost = false;
  String _myRequestStatus = ''; // '', 'pending', 'approved', 'denied'

  // ---- Display name cache (profile.teamName) ----
  final Map<String, String> _displayNameByUserId = <String, String>{};
  final Set<String> _displayNameLoading = <String>{};

  String _youLabel = 'You';

  DocumentReference<Map<String, dynamic>> get _spaceDoc => _firestore
      .collection('leagues')
      .doc(widget.leagueId)
      .collection('space')
      .doc('current');

  CollectionReference<Map<String, dynamic>> get _requestsCol => _spaceDoc.collection('requests');
  CollectionReference<Map<String, dynamic>> get _speakersCol => _spaceDoc.collection('speakers');

  DocumentReference<Map<String, dynamic>> get _myRequestDoc => _requestsCol.doc(_uid);
  DocumentReference<Map<String, dynamic>> get _mySpeakerDoc => _speakersCol.doc(_uid);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _youLabel = context.l10n.tr('common_you');
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  String _shortUid(String userId) {
    final s = userId.trim();
    if (s.length <= 10) return s;
    return '${s.substring(0, 6)}…${s.substring(s.length - 4)}';
  }

  String _displayName(String userId) {
    final cached = _displayNameByUserId[userId];
    if (cached != null && cached.trim().isNotEmpty) {
      if (userId == _uid) return '${cached.trim()} ($_youLabel)';
      return cached.trim();
    }
    // Fallback to a shortened uid to reduce "numbers and strings" feeling.
    if (userId == _uid) return '${_shortUid(userId)} ($_youLabel)';
    return _shortUid(userId);
  }

  void _ensureDisplayNameLoaded(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    if (_displayNameByUserId.containsKey(uid)) return;
    if (_displayNameLoading.contains(uid)) return;

    _displayNameLoading.add(uid);

    unawaited(() async {
      try {
        final profile = await _profiles.fetchByUserId(uid);
        final name = profile?.teamName.trim() ?? '';
        if (!mounted) return;

        setState(() {
          if (name.isNotEmpty) {
            _displayNameByUserId[uid] = name;
          }
        });
      } catch (_) {
        // ignore lookup errors (offline/permissions/etc). We keep fallback uid display.
      } finally {
        _displayNameLoading.remove(uid);
      }
    }());
  }

  Future<void> _init() async {
    final l10n = context.l10n;

    await SyncTrigger.trySync();

    final prefs = await PreferencesService.create();
    _uid = prefs.getCurrentUserId() ?? '';

    // Start resolving "You" display name early.
    _ensureDisplayNameLoaded(_uid);

    // IMPORTANT:
    // Await the mic permission request before any auto-connect/prime happens.
    await _requestMicPermissionOnJoin();

    _spaceSub = _spaceDoc.snapshots().listen((snap) async {
      if (!mounted) return;

      if (!snap.exists) {
        setState(() {
          _space = null;
          _loading = false;
          _error = '';
        });
        await _disconnectAudio();
        return;
      }

      try {
        final data = snap.data() ?? <String, dynamic>{};
        final space = LeagueSpace.fromJson(data);

        // Resolve host display name for nicer UI.
        _ensureDisplayNameLoaded(space.hostUserId);

        setState(() {
          _space = space;
          _loading = false;
          _error = '';
        });

        // once we have uid + a space doc, attach speaker/request listeners
        _ensureSpaceRoleListeners();

        // Twitter Spaces: join already connected to audio
        _autoConnectIfNeeded();

        // if Space ended while connected, disconnect audio
        if (!_isLive && _connected) {
          await _disconnectAudio();
        }
      } catch (e) {
        setState(() {
          _loading = false;
          _error = '${l10n.tr('league_space_failed_to_parse_space_prefix')} $e';
        });
      }
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '${l10n.tr('league_space_stream_error_prefix')} $e';
      });
    });
  }

  Future<bool> _requestMicPermissionOnJoin() async {
    if (_requestedMicPermissionOnJoin) {
      final st = await Permission.microphone.status;
      return st.isGranted;
    }
    _requestedMicPermissionOnJoin = true;
    try {
      final st = await Permission.microphone.request();
      return st.isGranted;
    } catch (_) {
      return false;
    }
  }

  void _autoConnectIfNeeded() {
    if (_joiningAudio || _connected) return;
    if (_uid.isEmpty) return;
    if (!_isLive) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_joiningAudio || _connected) return;
      if (_uid.isEmpty) return;
      if (!_isLive) return;
      _connectAudio();
    });
  }

  void _ensureSpaceRoleListeners() {
    final l10n = context.l10n;

    if (_uid.isEmpty) return;
    if (_space == null) return;

    // Host is always speaker-approved.
    if (_isHost) {
      if (!_isSpeakerApproved || _speakerMutedByHost) {
        setState(() {
          _isSpeakerApproved = true;
          _speakerMutedByHost = false;
          _myRequestStatus = '';
        });
      }
      _syncMicWithSpaceState();
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

      // Twitter Spaces behavior:
      // speaker approval is instant and does NOT reconnect/refresh/republish.
      // It only toggles mute/unmute of the already-published mic track.
      await _syncMicWithSpaceState();

      if (wasApproved != approved && approved) _toast(l10n.tr('league_space_toast_now_speaker'));
      if (wasApproved != approved && !approved) _toast(l10n.tr('league_space_toast_now_listener'));
      if (prevMuted != muted && muted) _toast(l10n.tr('league_space_toast_host_muted_you'));
      if (prevMuted != muted && !muted && approved) _toast(l10n.tr('league_space_toast_host_unmuted_you'));
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

    unawaited(_disconnectAudio());
    super.dispose();
  }

  bool get _isLive => _space?.isLive == true;
  bool get _isHost => _space != null && _uid.isNotEmpty && _space!.hostUserId == _uid;

  Future<void> _maybeStartAudioPlayback(Room room) async {
    // Best-effort: some platforms require explicit audio start.
    try {
      await (room as dynamic).startAudio();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _connectAudio() async {
    final l10n = context.l10n;

    if (_joiningAudio || _connected) return;
    if (!_isLive) return;
    if (_uid.isEmpty) return;

    setState(() {
      _joiningAudio = true;
      _error = '';
    });

    try {
      // Ensure mic permission decision is final BEFORE join/prime.
      await _requestMicPermissionOnJoin();

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

      _listener!.on<RoomDisconnectedEvent>((event) {
        if (!mounted) return;
        setState(() {
          _connected = false;
          _micEnabled = false;
          _micPrimed = false;
        });
      });

      await room.connect(token.url, token.token);

      // Start playback (best-effort)
      await _maybeStartAudioPlayback(room);

      if (!mounted) return;

      setState(() {
        _room = room;
        _connected = true;
      });

      // Prime mic publication ON JOIN (exactly once), then enforce listener vs speaker via mute state.
      await _primeMicPublicationOnJoin();

      // Apply current Firestore speaker state.
      await _syncMicWithSpaceState();

      if (!mounted) return;
      setState(() {
        _joiningAudio = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joiningAudio = false;
        _error = '${l10n.tr('league_space_audio_connect_failed_prefix')} $e';
      });
    }
  }

  Future<void> _primeMicPublicationOnJoin() async {
    if (_room == null) return;
    if (_micPrimed) return;

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      // User can still listen; but cannot become a speaker instantly later without republish.
      // This matches: approval must only unmute an already-published track.
      return;
    }

    try {
      // This call creates + publishes the mic track if it doesn't exist.
      // After this, further mic changes are mute/unmute only (no republish).
      await _room!.localParticipant!.setMicrophoneEnabled(true);
      _micPrimed = true;
      _micEnabled = true;
    } catch (e) {
      debugPrint('Mic prime failed on join: $e');
      _micPrimed = false;
      _micEnabled = false;
    }
  }

  Future<void> _syncMicWithSpaceState() async {
    final l10n = context.l10n;

    if (!_connected || _room == null) return;

    final shouldBeUnmuted = _isHost || (_isSpeakerApproved && !_speakerMutedByHost);

    // If mic wasn't primed at join, we refuse to enable later (that would publish on approval).
    if (!_micPrimed) {
      if (shouldBeUnmuted) {
        _toast(l10n.tr('league_space_mic_not_primed_toast'));
      }
      return;
    }

    await _setMicEnabled(shouldBeUnmuted);
  }

  Future<void> _setMicEnabled(bool enabled) async {
    if (_room == null) return;
    if (!_micPrimed) return;

    try {
      // With a primed mic track, this is a mute/unmute (no republish).
      await _room!.localParticipant!.setMicrophoneEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _micEnabled = enabled;
      });
    } catch (e) {
      debugPrint('setMicrophoneEnabled($enabled) failed: $e');
    }
  }

  Future<void> _disconnectAudio() async {
    try {
      _listener?.dispose();
      _listener = null;

      try {
        await _room?.disconnect();
      } catch (_) {}

      try {
        await _room?.dispose();
      } catch (_) {}
    } catch (_) {}

    _room = null;
    _connected = false;
    _joiningAudio = false;
    _micEnabled = false;
    _micPrimed = false;
  }

  bool get _canToggleMic {
    if (_room == null || !_connected) return false;
    if (!_micPrimed) return false;
    if (_isHost) return true;
    if (!_isSpeakerApproved) return false;
    if (_speakerMutedByHost) return false;
    return true;
  }

  Future<void> _toggleMic() async {
    final l10n = context.l10n;

    if (_room == null) return;

    if (!_canToggleMic) {
      if (!_micPrimed) {
        _toast(l10n.tr('league_space_mic_unavailable_permission_denied'));
      } else if (_isHost) {
        _toast(l10n.tr('league_space_mic_unavailable'));
      } else if (_speakerMutedByHost) {
        _toast(l10n.tr('league_space_you_are_muted_by_host'));
      } else if (!_isSpeakerApproved) {
        _toast(l10n.tr('league_space_request_to_speak_to_enable_mic'));
      }
      return;
    }

    final next = !_micEnabled;
    await _setMicEnabled(next);
    _toast(next ? l10n.tr('league_space_mic_on') : l10n.tr('league_space_mic_off'));
  }

  Future<void> _requestToSpeak() async {
    final l10n = context.l10n;

    if (_uid.isEmpty) return;
    if (_space == null) return;
    if (_isHost) return;
    if (!_isLive) {
      _toast(l10n.tr('league_space_space_not_live'));
      return;
    }

    try {
      await _myRequestDoc.set({
        'userId': _uid,
        'status': 'pending',
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      _toast(l10n.tr('league_space_request_sent'));
    } catch (e) {
      _toast('${l10n.tr('league_space_request_failed_prefix')} $e');
    }
  }

  Future<void> _withdrawRequest() async {
    final l10n = context.l10n;

    if (_uid.isEmpty) return;
    try {
      await _myRequestDoc.delete();
      _toast(l10n.tr('league_space_request_removed'));
    } catch (e) {
      _toast('${l10n.tr('league_space_failed_prefix')} $e');
    }
  }

  Future<void> _approveRequest(String userId) async {
    final l10n = context.l10n;

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
    _toast('${l10n.tr('league_space_approved_prefix')}${_displayName(userId)}');
  }

  Future<void> _denyRequest(String userId) async {
    final l10n = context.l10n;

    if (!_isHost) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    await _requestsCol.doc(userId).set({
      'userId': userId,
      'status': 'denied',
      'updatedAtMs': now,
    }, SetOptions(merge: true));

    // ensure not speaker
    await _speakersCol.doc(userId).delete().catchError((_) {});
    _toast('${l10n.tr('league_space_denied_prefix')}${_displayName(userId)}');
  }

  Future<void> _removeSpeaker(String userId) async {
    final l10n = context.l10n;

    if (!_isHost) return;
    await _speakersCol.doc(userId).delete();
    _toast('${l10n.tr('league_space_removed_speaker_prefix')}${_displayName(userId)}');
  }

  Future<void> _toggleMuteSpeaker(String userId, bool muted) async {
    final l10n = context.l10n;

    if (!_isHost) return;
    await _speakersCol.doc(userId).set({'muted': muted}, SetOptions(merge: true));
    _toast(muted ? '${l10n.tr('league_space_muted_prefix')}${_displayName(userId)}' : '${l10n.tr('league_space_unmuted_prefix')}${_displayName(userId)}');
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
    final l10n = context.l10n;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_space_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('league_details_sync_tooltip'),
            onPressed: () async {
              await SyncTrigger.trySync();
              _toast(l10n.tr('league_details_synced_toast'));
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
                            ? Center(
                                child: Text(
                                  l10n.tr('league_space_no_active_space'),
                                  style: const TextStyle(color: Colors.white70),
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
    final l10n = context.l10n;

    final space = _space!;
    _ensureDisplayNameLoaded(space.hostUserId);

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
                space.title ?? l10n.tr('league_space_default_title'),
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
                border: Border.all(
                  color: _isLive ? Colors.redAccent.withOpacity(0.6) : Colors.white24,
                ),
              ),
              child: Text(
                _isLive ? l10n.tr('league_space_live_badge') : l10n.tr('league_space_ended_badge'),
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
        Text(
          '${l10n.tr('league_space_host_prefix')}${_displayName(space.hostUserId)}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
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
                            : Icon(_connected ? Icons.call_end : Icons.headset_mic),
                        label: Text(_connected ? l10n.tr('league_space_leave_audio') : l10n.tr('league_space_join_audio')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _canToggleMic ? _toggleMic : null,
                        icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                        label: Text(_micEnabled ? l10n.tr('league_space_mic_on') : l10n.tr('league_space_mic_off')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _connected
                      ? (_isHost
                          ? l10n.tr('league_space_connected_as_host')
                          : (_isSpeakerApproved
                              ? (_speakerMutedByHost
                                  ? l10n.tr('league_space_connected_as_speaker_muted_by_host')
                                  : l10n.tr('league_space_connected_as_speaker'))
                              : l10n.tr('league_space_connected_as_listener')))
                      : l10n.tr('league_space_not_connected'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (!_isHost) ...[
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_isLive && !_isSpeakerApproved && _myRequestStatus != 'pending') ? _requestToSpeak : null,
                          icon: const Icon(Icons.record_voice_over),
                          label: Text(
                            _isSpeakerApproved
                                ? l10n.tr('league_space_you_are_speaker')
                                : (_myRequestStatus == 'pending' ? l10n.tr('league_space_request_pending') : l10n.tr('league_space_request_to_speak')),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: (_myRequestStatus == 'pending') ? _withdrawRequest : null,
                        child: Text(l10n.tr('common_cancel')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_myRequestStatus == 'denied')
                    Text(
                      l10n.tr('league_space_request_denied'),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isHost) ...[
          Glass(
            borderRadius: 16,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.tr('league_space_host_panel_title'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.tr('league_space_requests_title'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _requestsCol.where('status', isEqualTo: 'pending').snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Text(
                          '${l10n.tr('league_space_requests_error_prefix')} ${snap.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();

                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Text(l10n.tr('league_space_no_pending_requests'), style: const TextStyle(color: Colors.white38));
                      }

                      return Column(
                        children: docs.map((doc) {
                          final d = doc.data();
                          final userId = (d['userId'] ?? doc.id).toString();
                          _ensureDisplayNameLoaded(userId);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                _displayName(userId),
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${l10n.tr('league_space_uid_prefix')}${_shortUid(userId)} ${l10n.tr('league_space_wants_to_speak_suffix')}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _denyRequest(userId);
                                      } catch (e) {
                                        _toast('${l10n.tr('league_space_deny_failed_prefix')} $e');
                                      }
                                    },
                                    child: Text(l10n.tr('league_space_deny')),
                                  ),
                                  FilledButton(
                                    onPressed: () async {
                                      try {
                                        await _approveRequest(userId);
                                      } catch (e) {
                                        _toast('${l10n.tr('league_space_approve_failed_prefix')} $e');
                                      }
                                    },
                                    child: Text(l10n.tr('league_space_approve')),
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
                  Text(
                    l10n.tr('league_space_speakers_title'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _speakersCol.orderBy('approvedAtMs', descending: false).snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Text(
                          '${l10n.tr('league_space_speakers_error_prefix')} ${snap.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();

                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Text(l10n.tr('league_space_no_speakers_yet'), style: const TextStyle(color: Colors.white38));
                      }

                      return Column(
                        children: docs.map((doc) {
                          final d = doc.data();
                          final userId = (d['userId'] ?? doc.id).toString();
                          final muted = d['muted'] == true;

                          _ensureDisplayNameLoaded(userId);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                _displayName(userId),
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${l10n.tr('league_space_uid_prefix')}${_shortUid(userId)} • ${muted ? l10n.tr('league_space_muted') : l10n.tr('league_space_unmuted')}',
                                style: TextStyle(
                                  color: muted ? Colors.orangeAccent : Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _toggleMuteSpeaker(userId, !muted);
                                      } catch (e) {
                                        _toast('${l10n.tr('league_space_mute_failed_prefix')} $e');
                                      }
                                    },
                                    child: Text(muted ? l10n.tr('league_space_unmute') : l10n.tr('league_space_mute')),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _removeSpeaker(userId);
                                      } catch (e) {
                                        _toast('${l10n.tr('league_space_remove_failed_prefix')} $e');
                                      }
                                    },
                                    child: Text(l10n.tr('league_space_remove')),
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
