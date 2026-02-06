import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/platform/overlay_bridge.dart';
import '../../../core/platform/overlay_platform.dart';
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
  bool _micPrimed = false;

  bool _requestedMicPermissionOnJoin = false;

  // ---- Overlay/FGS integration ----
  bool _voiceFgsRunning = false;

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
        // ignore
      } finally {
        _displayNameLoading.remove(uid);
      }
    }());
  }

  Color _baseToastBg(ThemeData theme) {
    return theme.brightness == Brightness.dark ? const Color(0xFF101522) : const Color(0xFF0F172A);
  }

  void _toast(String msg, {Color? accent, IconData? icon}) {
    if (!mounted) return;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final baseBg = _baseToastBg(theme);
    final fg = accent ?? Colors.white;
    final bg = accent == null ? baseBg : Color.alphaBlend(accent.withOpacity(0.22), baseBg);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: bg,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: cs.brightness == Brightness.dark ? '' : '',
          onPressed: () {},
          textColor: Colors.transparent,
          disabledTextColor: Colors.transparent,
        ),
      ),
    );
  }

  void _toastOk(String msg) {
    final cs = Theme.of(context).colorScheme;
    _toast(msg, accent: cs.primary, icon: Icons.check_circle_outline);
  }

  void _toastWarn(String msg) {
    const warn = Color(0xFFF59E0B);
    _toast(msg, accent: warn, icon: Icons.warning_amber_rounded);
  }

  void _toastErr(String msg) {
    final cs = Theme.of(context).colorScheme;
    _toast(msg, accent: cs.error, icon: Icons.error_outline);
  }

  Future<void> _init() async {
    final l10n = context.l10n;

    await SyncTrigger.trySync();

    final prefs = await PreferencesService.create();
    _uid = prefs.getCurrentUserId() ?? '';

    _ensureDisplayNameLoaded(_uid);

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

        _ensureDisplayNameLoaded(space.hostUserId);

        setState(() {
          _space = space;
          _loading = false;
          _error = '';
        });

        _ensureSpaceRoleListeners();
        _autoConnectIfNeeded();

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

      await _syncMicWithSpaceState();

      if (wasApproved != approved && approved) _toastOk(l10n.tr('league_space_toast_now_speaker'));
      if (wasApproved != approved && !approved) _toast(l10n.tr('league_space_toast_now_listener'));
      if (prevMuted != muted && muted) _toastWarn(l10n.tr('league_space_toast_host_muted_you'));
      if (prevMuted != muted && !muted && approved) _toastOk(l10n.tr('league_space_toast_host_unmuted_you'));
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

    OverlayBridge.clearHandlers();
    unawaited(_disconnectAudio());
    super.dispose();
  }

  bool get _isLive => _space?.isLive == true;
  bool get _isHost => _space != null && _uid.isNotEmpty && _space!.hostUserId == _uid;

  Future<void> _maybeStartAudioPlayback(Room room) async {
    try {
      await (room as dynamic).startAudio();
    } catch (_) {}
  }

  Future<void> _startVoiceFgs() async {
    if (_voiceFgsRunning) return;

    final mic = await Permission.microphone.status;
    if (!mic.isGranted) return;

    try {
      final st = await Permission.notification.status;
      if (!st.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}

    final title = 'Voice chat';
    final text = (_space?.title?.trim().isNotEmpty == true) ? (_space!.title!.trim()) : 'Space audio is running';

    try {
      await OverlayPlatform.startOverlayVoiceForegroundService(
        title: title,
        text: text,
      );
      _voiceFgsRunning = true;
    } catch (_) {
      _voiceFgsRunning = false;
    }
  }

  Future<void> _stopVoiceFgs() async {
    if (!_voiceFgsRunning) return;
    try {
      await OverlayPlatform.stopOverlayVoiceForegroundService();
    } catch (_) {}
    _voiceFgsRunning = false;
  }

  void _registerOverlayHandlersForSpace() {
    OverlayBridge.setMicEnabled = (enabled) async {
      if (!_connected || _room == null) return;
      if (!_micPrimed) return;

      if (enabled) {
        await _syncMicWithSpaceState();
        return;
      }

      await _setMicEnabled(false);
    };

    OverlayBridge.toggleMic = () async {
      if (!_connected || _room == null) return;
      await _toggleMic();
    };

    OverlayBridge.endSession = () async {
      await _disconnectAudio();
    };

    OverlayBridge.sendQuick = null;
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
        // Best-effort: show muted icon when session ends.
        unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
      });

      await room.connect(token.url, token.token);
      await _maybeStartAudioPlayback(room);

      if (!mounted) return;

      setState(() {
        _room = room;
        _connected = true;
      });

      await _primeMicPublicationOnJoin();
      await _syncMicWithSpaceState();

      _registerOverlayHandlersForSpace();
      await _startVoiceFgs();

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
    if (!micStatus.isGranted) return;

    try {
      await _room!.localParticipant!.setMicrophoneEnabled(true);
      _micPrimed = true;
      _micEnabled = true;
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: false));
    } catch (e) {
      debugPrint('Mic prime failed on join: $e');
      _micPrimed = false;
      _micEnabled = false;
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
    }
  }

  Future<void> _syncMicWithSpaceState() async {
    final l10n = context.l10n;

    if (!_connected || _room == null) return;

    final shouldBeUnmuted = _isHost || (_isSpeakerApproved && !_speakerMutedByHost);

    if (!_micPrimed) {
      if (shouldBeUnmuted) {
        _toastWarn(l10n.tr('league_space_mic_not_primed_toast'));
      }
      // Keep overlay icon muted if we cannot unmute.
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
      return;
    }

    await _setMicEnabled(shouldBeUnmuted);
  }

  Future<void> _setMicEnabled(bool enabled) async {
    if (_room == null) return;
    if (!_micPrimed) return;

    try {
      await _room!.localParticipant!.setMicrophoneEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _micEnabled = enabled;
      });

      // Push real mic state to Android overlay icon.
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: !enabled));
    } catch (e) {
      debugPrint('setMicrophoneEnabled($enabled) failed: $e');
    }
  }

  Future<void> _disconnectAudio() async {
    await _stopVoiceFgs();
    OverlayBridge.clearHandlers();

    // Best-effort: when no active voice, show muted icon.
    unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));

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
        _toastWarn(l10n.tr('league_space_mic_unavailable_permission_denied'));
      } else if (_isHost) {
        _toastWarn(l10n.tr('league_space_mic_unavailable'));
      } else if (_speakerMutedByHost) {
        _toastWarn(l10n.tr('league_space_you_are_muted_by_host'));
      } else if (!_isSpeakerApproved) {
        _toastWarn(l10n.tr('league_space_request_to_speak_to_enable_mic'));
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
      _toastWarn(l10n.tr('league_space_space_not_live'));
      return;
    }

    try {
      await _myRequestDoc.set({
        'userId': _uid,
        'status': 'pending',
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
      _toastOk(l10n.tr('league_space_request_sent'));
    } catch (e) {
      _toastErr('${l10n.tr('league_space_request_failed_prefix')} $e');
    }
  }

  Future<void> _withdrawRequest() async {
    final l10n = context.l10n;

    if (_uid.isEmpty) return;
    try {
      await _myRequestDoc.delete();
      _toastOk(l10n.tr('league_space_request_removed'));
    } catch (e) {
      _toastErr('${l10n.tr('league_space_failed_prefix')} $e');
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
    _toastOk('${l10n.tr('league_space_approved_prefix')}${_displayName(userId)}');
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

    await _speakersCol.doc(userId).delete().catchError((_) {});
    _toastWarn('${l10n.tr('league_space_denied_prefix')}${_displayName(userId)}');
  }

  Future<void> _removeSpeaker(String userId) async {
    final l10n = context.l10n;

    if (!_isHost) return;
    await _speakersCol.doc(userId).delete();
    _toastWarn('${l10n.tr('league_space_removed_speaker_prefix')}${_displayName(userId)}');
  }

  Future<void> _toggleMuteSpeaker(String userId, bool muted) async {
    final l10n = context.l10n;

    if (!_isHost) return;
    await _speakersCol.doc(userId).set({'muted': muted}, SetOptions(merge: true));
    _toast(muted
        ? '${l10n.tr('league_space_muted_prefix')}${_displayName(userId)}'
        : '${l10n.tr('league_space_unmuted_prefix')}${_displayName(userId)}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
              _toastOk(l10n.tr('league_details_synced_toast'));
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
                    ? Center(child: CircularProgressIndicator(color: cs.primary))
                    : _error.isNotEmpty
                        ? Center(
                            child: Text(
                              _error,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface.withOpacity(0.72),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _space == null
                            ? Center(
                                child: Text(
                                  l10n.tr('league_space_no_active_space'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface.withOpacity(0.72),
                                    fontWeight: FontWeight.w600,
                                  ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final space = _space!;
    _ensureDisplayNameLoaded(space.hostUserId);

    final liveBadgeBg = _isLive ? cs.error.withOpacity(0.14) : cs.onSurface.withOpacity(0.06);
    final liveBadgeStroke = _isLive ? cs.error.withOpacity(0.50) : cs.onSurface.withOpacity(0.18);
    final liveBadgeFg = _isLive ? cs.error : cs.onSurface.withOpacity(0.55);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              _isLive ? Icons.graphic_eq : Icons.spatial_audio_off,
              color: _isLive ? cs.primary : cs.onSurface.withOpacity(0.45),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                space.title ?? l10n.tr('league_space_default_title'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: liveBadgeBg,
                border: Border.all(color: liveBadgeStroke),
              ),
              child: Text(
                _isLive ? l10n.tr('league_space_live_badge') : l10n.tr('league_space_ended_badge'),
                style: TextStyle(
                  color: liveBadgeFg,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${l10n.tr('league_space_host_prefix')}${_displayName(space.hostUserId)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.65),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
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
                                : (_myRequestStatus == 'pending'
                                    ? l10n.tr('league_space_request_pending')
                                    : l10n.tr('league_space_request_to_speak')),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.tr('league_space_requests_title'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _requestsCol.where('status', isEqualTo: 'pending').snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Text(
                          '${l10n.tr('league_space_requests_error_prefix')} ${snap.error}',
                          style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();

                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Text(
                          l10n.tr('league_space_no_pending_requests'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.45),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }

                      return Column(
                        children: docs.map((doc) {
                          final d = doc.data();
                          final userId = (d['userId'] ?? doc.id).toString();
                          _ensureDisplayNameLoaded(userId);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                _displayName(userId),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                '${l10n.tr('league_space_uid_prefix')}${_shortUid(userId)} ${l10n.tr('league_space_wants_to_speak_suffix')}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _denyRequest(userId);
                                      } catch (e) {
                                        _toastErr('${l10n.tr('league_space_deny_failed_prefix')} $e');
                                      }
                                    },
                                    child: Text(l10n.tr('league_space_deny')),
                                  ),
                                  FilledButton(
                                    onPressed: () async {
                                      try {
                                        await _approveRequest(userId);
                                      } catch (e) {
                                        _toastErr('${l10n.tr('league_space_approve_failed_prefix')} $e');
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _speakersCol.orderBy('approvedAtMs', descending: false).snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Text(
                          '${l10n.tr('league_space_speakers_error_prefix')} ${snap.error}',
                          style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();

                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return Text(
                          l10n.tr('league_space_no_speakers_yet'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.45),
                            fontWeight: FontWeight.w600,
                          ),
                        );
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
                              color: cs.onSurface.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.onSurface.withOpacity(0.12)),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                _displayName(userId),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                '${l10n.tr('league_space_uid_prefix')}${_shortUid(userId)} • ${muted ? l10n.tr('league_space_muted') : l10n.tr('league_space_unmuted')}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted ? const Color(0xFFF59E0B) : cs.onSurface.withOpacity(0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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
                                        _toastErr('${l10n.tr('league_space_mute_failed_prefix')} $e');
                                      }
                                    },
                                    child: Text(muted ? l10n.tr('league_space_unmute') : l10n.tr('league_space_mute')),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        await _removeSpeaker(userId);
                                      } catch (e) {
                                        _toastErr('${l10n.tr('league_space_remove_failed_prefix')} $e');
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
