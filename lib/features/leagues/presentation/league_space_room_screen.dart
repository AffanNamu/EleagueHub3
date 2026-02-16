import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/platform/overlay_bridge.dart';
import '../../../core/platform/overlay_platform.dart';
import '../../../core/services/connectivity_service.dart';
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

  bool _micEnabled = false;
  bool _micPrimed = false;

  bool _requestedMicPermissionOnJoin = false;

  bool _voiceFgsRunning = false;

  // ── Reconnection state ──
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mySpeakerSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myRequestSub;

  bool _isSpeakerApproved = false;
  bool _speakerMutedByHost = false;
  String _myRequestStatus = '';

  final Map<String, String> _displayNameByUserId = <String, String>{};
  final Set<String> _displayNameLoading = <String>{};
  final Map<String, String> _avatarUrlByUserId = <String, String>{};

  String _youLabel = 'You';

  DocumentReference<Map<String, dynamic>> get _spaceDoc =>
      _firestore.collection('leagues').doc(widget.leagueId).collection('space').doc('current');

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
    unawaited(_init());
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

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(String url, {int width = 96, int height = 96}) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final isCloudinary = u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;
    final marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;
    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);
    final transforms = 'f_auto,q_auto,w_$width,h_$height,c_fill,g_auto';
    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';
    final first = parts.first;
    final isVersionOnly = first.startsWith('v') && int.tryParse(first.substring(1)) != null;
    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }
    return '$prefix$transforms/$suffix';
  }

  String _bestEffortProfileImageUrlFromProfile(dynamic profile) {
    if (profile == null) return '';
    String url = '';
    try { final v = (profile.photoUrl as String?) ?? ''; if (v.trim().isNotEmpty) url = v.trim(); } catch (_) {}
    if (url.isEmpty) { try { final v = (profile.profileImageUrl as String?) ?? ''; if (v.trim().isNotEmpty) url = v.trim(); } catch (_) {} }
    if (url.isEmpty) { try { final v = (profile.teamImageUrl as String?) ?? ''; if (v.trim().isNotEmpty) url = v.trim(); } catch (_) {} }
    return url.trim();
  }

  void _ensureDisplayNameLoaded(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    final hasName = (_displayNameByUserId[uid] ?? '').trim().isNotEmpty;
    final hasAvatar = _avatarUrlByUserId.containsKey(uid);
    if (hasName && hasAvatar) return;
    if (_displayNameLoading.contains(uid)) return;
    _displayNameLoading.add(uid);

    unawaited(() async {
      try {
        final profile = await _profiles.fetchByUserId(uid).timeout(const Duration(seconds: 10));
        String name = '';
        try { name = (profile.teamName as String?)?.trim() ?? ''; } catch (_) {}
        final avatar = _bestEffortProfileImageUrlFromProfile(profile).trim();
        if (!mounted) return;
        setState(() {
          if (name.isNotEmpty) _displayNameByUserId[uid] = name;
          if (avatar.isNotEmpty) _avatarUrlByUserId[uid] = avatar;
          else _avatarUrlByUserId.putIfAbsent(uid, () => '');
        });
      } catch (_) {}
      finally { _displayNameLoading.remove(uid); }
    }());
  }

  String _avatarUrl(String userId) {
    final raw = (_avatarUrlByUserId[userId] ?? '').trim();
    if (raw.isEmpty) return '';
    if (_looksLikeHttpUrl(raw)) return _cloudinaryOptimizedUrl(raw, width: 96, height: 96);
    return raw;
  }

  void _toast(String msg, {Color? accent, IconData? icon}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    final baseBg = theme.brightness == Brightness.dark ? const Color(0xFF101522) : const Color(0xFF0F172A);
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
            if (icon != null) ...[Icon(icon, color: fg, size: 18), const SizedBox(width: 10)],
            Expanded(child: Text(msg, style: TextStyle(color: fg, fontWeight: FontWeight.w700))),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toastOk(String msg) => _toast(msg, accent: Theme.of(context).colorScheme.primary, icon: Icons.check_circle_outline);
  void _toastWarn(String msg) => _toast(msg, accent: const Color(0xFFF59E0B), icon: Icons.warning_amber_rounded);
  void _toastErr(String msg) => _toast(msg, accent: Theme.of(context).colorScheme.error, icon: Icons.error_outline);

  /// User-friendly connection error message
  String _friendlyConnectionError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return 'Connection timed out. Please check your internet and try again.';
    }
    if (raw.contains('no internet') || raw.contains('offline') || raw.contains('network')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (raw.contains('permission') || raw.contains('denied')) {
      return 'Microphone permission is required to join voice chat.';
    }
    if (raw.contains('token') || raw.contains('auth') || raw.contains('401') || raw.contains('403')) {
      return 'Authentication failed. Please sign out and sign back in.';
    }
    if (raw.contains('room') || raw.contains('livekit') || raw.contains('websocket') || raw.contains('connect')) {
      return 'Could not connect to voice server. Retrying...';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _init() async {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (authUid.isEmpty) {
      if (mounted) context.go('/login');
      return;
    }

    _uid = authUid;
    _ensureDisplayNameLoaded(_uid);

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyConnectionError(e);
      });
      return;
    }

    await _requestMicPermissionOnJoinFn();

    _spaceSub = _spaceDoc.snapshots(includeMetadataChanges: true).listen((snap) async {
      if (!mounted) return;
      if (snap.metadata.isFromCache) return;

      if (!snap.exists) {
        setState(() { _space = null; _loading = false; _error = ''; });
        await _disconnectAudio();
        return;
      }

      try {
        final data = snap.data() ?? <String, dynamic>{};
        final space = LeagueSpace.fromJson(data);
        _ensureDisplayNameLoaded(space.hostUserId);
        setState(() { _space = space; _loading = false; _error = ''; });
        _ensureSpaceRoleListeners();
        _autoConnectIfNeeded();
        if (!_isLive && _connected) await _disconnectAudio();
      } catch (e) {
        setState(() { _loading = false; _error = _friendlyConnectionError(e); });
      }
    }, onError: (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _friendlyConnectionError(e); });
    });
  }

  Future<bool> _requestMicPermissionOnJoinFn() async {
    if (_requestedMicPermissionOnJoin) {
      final st = await Permission.microphone.status;
      return st.isGranted;
    }
    _requestedMicPermissionOnJoin = true;
    try {
      final st = await Permission.microphone.request();
      return st.isGranted;
    } catch (_) { return false; }
  }

  void _autoConnectIfNeeded() {
    if (_joiningAudio || _connected) return;
    if (_uid.isEmpty || !_isLive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _joiningAudio || _connected || _uid.isEmpty || !_isLive) return;
      _connectAudio();
    });
  }

  void _ensureSpaceRoleListeners() {
    final l10n = context.l10n;
    if (_uid.isEmpty || _space == null) return;

    if (_isHost) {
      if (!_isSpeakerApproved || _speakerMutedByHost) {
        setState(() { _isSpeakerApproved = true; _speakerMutedByHost = false; _myRequestStatus = ''; });
      }
      unawaited(_syncMicWithSpaceState());
      return;
    }

    _mySpeakerSub ??= _mySpeakerDoc.snapshots(includeMetadataChanges: true).listen((snap) async {
      if (snap.metadata.isFromCache) return;
      final approved = snap.exists;
      final muted = (snap.data()?['muted'] == true);
      final wasApproved = _isSpeakerApproved;
      final prevMuted = _speakerMutedByHost;
      if (!mounted) return;
      setState(() { _isSpeakerApproved = approved; _speakerMutedByHost = muted; });
      await _syncMicWithSpaceState();
      if (wasApproved != approved && approved) _toastOk(l10n.tr('league_space_toast_now_speaker'));
      if (wasApproved != approved && !approved) _toast(l10n.tr('league_space_toast_now_listener'));
      if (prevMuted != muted && muted) _toastWarn(l10n.tr('league_space_toast_host_muted_you'));
      if (prevMuted != muted && !muted && approved) _toastOk(l10n.tr('league_space_toast_host_unmuted_you'));
    });

    _myRequestSub ??= _myRequestDoc.snapshots(includeMetadataChanges: true).listen((snap) {
      if (snap.metadata.isFromCache) return;
      if (!mounted) return;
      if (!snap.exists) { setState(() => _myRequestStatus = ''); return; }
      final status = (snap.data()?['status'] ?? '').toString();
      setState(() => _myRequestStatus = status);
    });
  }

  @override
  void dispose() {
    _spaceSub?.cancel();
    _mySpeakerSub?.cancel();
    _myRequestSub?.cancel();
    _reconnectTimer?.cancel();
    OverlayBridge.clearHandlers();
    unawaited(_disconnectAudio());
    super.dispose();
  }

  bool get _isLive => _space?.isLive == true;
  bool get _isHost => _space != null && _uid.isNotEmpty && _space!.hostUserId == _uid;

  Future<void> _maybeStartAudioPlayback(Room room) async {
    try { await (room as dynamic).startAudio(); } catch (_) {}
  }

  Future<void> _startVoiceFgs() async {
    if (_voiceFgsRunning) return;
    final mic = await Permission.microphone.status;
    if (!mic.isGranted) return;
    try {
      final st = await Permission.notification.status;
      if (!st.isGranted) await Permission.notification.request();
    } catch (_) {}
    final title = 'Voice chat';
    final text = (_space?.title?.trim().isNotEmpty == true) ? _space!.title!.trim() : 'Space audio is running';
    try {
      await OverlayPlatform.startOverlayVoiceForegroundService(title: title, text: text);
      _voiceFgsRunning = true;
    } catch (_) { _voiceFgsRunning = false; }
  }

  Future<void> _stopVoiceFgs() async {
    if (!_voiceFgsRunning) return;
    try { await OverlayPlatform.stopOverlayVoiceForegroundService(); } catch (_) {}
    _voiceFgsRunning = false;
  }

  void _registerOverlayHandlersForSpace() {
    OverlayBridge.setMicEnabled = (enabled) async {
      if (!_connected || _room == null || !_micPrimed) return;
      if (enabled) { await _syncMicWithSpaceState(); return; }
      await _setMicEnabled(false);
    };
    OverlayBridge.toggleMic = () async {
      if (!_connected || _room == null) return;
      await _toggleMic();
    };
    OverlayBridge.endSession = () async { await _disconnectAudio(); };
    OverlayBridge.sendQuick = null;
  }

  /// Attempt reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (!mounted) return;
      setState(() {
        _isReconnecting = false;
        _error = 'Unable to reconnect after multiple attempts. Please try again manually.';
      });
      return;
    }

    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (2 << _reconnectAttempts).clamp(2, 30));
    _reconnectAttempts++;

    if (!mounted) return;
    setState(() => _isReconnecting = true);

    _reconnectTimer = Timer(delay, () {
      if (!mounted) return;
      if (!_isLive) {
        setState(() => _isReconnecting = false);
        return;
      }
      _connectAudio();
    });
  }

  Future<void> _connectAudio() async {
    if (_joiningAudio || _connected) return;
    if (!_isLive || _uid.isEmpty) return;

    setState(() { _joiningAudio = true; _error = ''; });

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _requestMicPermissionOnJoinFn();

      final token = await LiveKitService.fetchToken(
        leagueId: widget.leagueId,
        userId: _uid,
        isHost: _isHost,
      ).timeout(const Duration(seconds: 20));

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true, audioBitrate: 32000),
        ),
      );

      _listener = room.createListener();

      _listener!.on<RoomConnectedEvent>((event) {
        if (!mounted) return;
        setState(() { _connected = true; _isReconnecting = false; _reconnectAttempts = 0; });
      });

      _listener!.on<RoomDisconnectedEvent>((event) {
        if (!mounted) return;
        setState(() { _connected = false; _micEnabled = false; _micPrimed = false; });
        unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));

        // Auto-reconnect if space is still live
        if (_isLive && !_isReconnecting) {
          _toastWarn('Connection lost. Reconnecting...');
          _scheduleReconnect();
        }
      });

      await room.connect(token.url, token.token).timeout(const Duration(seconds: 25));
      await _maybeStartAudioPlayback(room);

      if (!mounted) return;

      setState(() { _room = room; _connected = true; _reconnectAttempts = 0; _isReconnecting = false; });

      await _primeMicPublicationOnJoin();
      await _syncMicWithSpaceState();
      _registerOverlayHandlersForSpace();
      await _startVoiceFgs();

      if (!mounted) return;
      setState(() => _joiningAudio = false);
    } catch (e) {
      if (!mounted) return;

      final friendlyMsg = _friendlyConnectionError(e);

      setState(() { _joiningAudio = false; });

      // If it looks like a transient error, try reconnecting
      final raw = e.toString().toLowerCase();
      final isTransient = raw.contains('timeout') || raw.contains('network') ||
          raw.contains('websocket') || raw.contains('connect') || raw.contains('offline');

      if (isTransient && _reconnectAttempts < _maxReconnectAttempts && _isLive) {
        _toastWarn('Reconnecting...');
        _scheduleReconnect();
      } else {
        setState(() => _error = friendlyMsg);
        _toastErr(friendlyMsg);
      }
    }
  }

  Future<void> _primeMicPublicationOnJoin() async {
    if (_room == null || _micPrimed) return;
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
    if (!_connected || _room == null) return;
    final shouldBeUnmuted = _isHost || (_isSpeakerApproved && !_speakerMutedByHost);
    if (!_micPrimed) {
      if (shouldBeUnmuted) {
        _toastWarn(context.l10n.tr('league_space_mic_not_primed_toast'));
      }
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));
      return;
    }
    await _setMicEnabled(shouldBeUnmuted);
  }

  Future<void> _setMicEnabled(bool enabled) async {
    if (_room == null || !_micPrimed) return;
    try {
      await _room!.localParticipant!.setMicrophoneEnabled(enabled);
      if (!mounted) return;
      setState(() => _micEnabled = enabled);
      unawaited(OverlayPlatform.setOverlayMicMutedState(muted: !enabled));
    } catch (e) { debugPrint('setMicrophoneEnabled($enabled) failed: $e'); }
  }

  Future<void> _disconnectAudio() async {
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    _reconnectAttempts = 0;

    await _stopVoiceFgs();
    OverlayBridge.clearHandlers();
    unawaited(OverlayPlatform.setOverlayMicMutedState(muted: true));

    try {
      _listener?.dispose();
      _listener = null;
      try { await _room?.disconnect(); } catch (_) {}
      try { await _room?.dispose(); } catch (_) {}
    } catch (_) {}

    _room = null;
    _connected = false;
    _joiningAudio = false;
    _micEnabled = false;
    _micPrimed = false;
  }

  bool get _canToggleMic {
    if (_room == null || !_connected || !_micPrimed) return false;
    if (_isHost) return true;
    if (!_isSpeakerApproved || _speakerMutedByHost) return false;
    return true;
  }

  Future<void> _toggleMic() async {
    final l10n = context.l10n;
    if (_room == null) return;
    if (!_canToggleMic) {
      if (!_micPrimed) _toastWarn(l10n.tr('league_space_mic_unavailable_permission_denied'));
      else if (_speakerMutedByHost) _toastWarn(l10n.tr('league_space_you_are_muted_by_host'));
      else if (!_isSpeakerApproved) _toastWarn(l10n.tr('league_space_request_to_speak_to_enable_mic'));
      else _toastWarn(l10n.tr('league_space_mic_unavailable'));
      return;
    }
    final next = !_micEnabled;
    await _setMicEnabled(next);
    _toast(next ? l10n.tr('league_space_mic_on') : l10n.tr('league_space_mic_off'));
  }

  Future<void> _requestToSpeak() async {
    final l10n = context.l10n;
    if (_uid.isEmpty || _space == null || _isHost) return;
    if (!_isLive) { _toastWarn(l10n.tr('league_space_space_not_live')); return; }
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      final now = DateTime.now().millisecondsSinceEpoch;
      await _myRequestDoc.set({
        'userId': _uid, 'status': 'pending', 'createdAtMs': now, 'updatedAtMs': now,
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
      _toastOk(l10n.tr('league_space_request_sent'));
    } catch (e) { _toastErr(_friendlyConnectionError(e)); }
  }

  Future<void> _withdrawRequest() async {
    final l10n = context.l10n;
    if (_uid.isEmpty) return;
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _myRequestDoc.delete().timeout(const Duration(seconds: 12));
      _toastOk(l10n.tr('league_space_request_removed'));
    } catch (e) { _toastErr(_friendlyConnectionError(e)); }
  }

  Future<void> _approveRequest(String userId) async {
    final l10n = context.l10n;
    if (!_isHost) return;
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      final batch = _firestore.batch();
      final now = DateTime.now().millisecondsSinceEpoch;
      batch.set(_speakersCol.doc(userId), {
        'userId': userId, 'approvedBy': _uid, 'approvedAtMs': now, 'muted': false,
      }, SetOptions(merge: true));
      batch.set(_requestsCol.doc(userId), {
        'userId': userId, 'status': 'approved', 'updatedAtMs': now,
      }, SetOptions(merge: true));
      await batch.commit().timeout(const Duration(seconds: 15));
      _toastOk('${l10n.tr('league_space_approved_prefix')}${_displayName(userId)}');
    } catch (e) { _toastErr(_friendlyConnectionError(e)); }
  }

  Future<void> _denyRequest(String userId) async {
    final l10n = context.l10n;
    if (!_isHost) return;
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      final now = DateTime.now().millisecondsSinceEpoch;
      await _requestsCol.doc(userId).set({
        'userId': userId, 'status': 'denied', 'updatedAtMs': now,
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
      await _speakersCol.doc(userId).delete().timeout(const Duration(seconds: 12));
      _toastWarn('${l10n.tr('league_space_denied_prefix')}${_displayName(userId)}');
    } catch (e) { _toastErr(_friendlyConnectionError(e)); }
  }

  Future<void> _removeSpeaker(String userId) async {
    final l10n = context.l10n;
    if (!_isHost) return;
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _speakersCol.doc(userId).delete().timeout(const Duration(seconds: 12));
      _toastWarn('${l10n.tr('league_space_removed_speaker_prefix')}${_displayName(userId)}');
    } catch (e) { _toastErr(_friendlyConnectionError(e)); }
  }

  Future<void> _toggleMuteSpeaker(String userId, bool muted) async {
    final l10n = context.l10n;
    if (!_isHost) return;
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _speakersCol.doc(userId).set({'muted': muted}, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
      _toast(muted
          ? '${l10n.tr('league_space_muted_prefix')}${_displayName(userId)}'
          : '${l10n.tr('league_space_unmuted_prefix')}${_displayName(userId)}');
    } catch (e) { _toastErr(_friendlyConnectionError(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Glass(
            padding: const EdgeInsets.all(8),
            borderRadius: 12,
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white.withOpacity(0.9)),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: l10n.tr('common_refresh'),
            onPressed: () async {
              final ok = await ConnectivityService.instance.recheckConnection();
              if (!mounted) return;
              _toastOk(ok ? l10n.tr('common_done') : l10n.tr('common_retry'));
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                // ── Header ──
                Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [cs.primary.withOpacity(0.30), cs.primary.withOpacity(0.08)],
                          ),
                        ),
                        child: Icon(Icons.spatial_audio_rounded, color: cs.primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.tr('league_space_appbar_title'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _loading ? 'Loading...' : (_connected ? 'Connected' : 'Not connected'),
                              style: TextStyle(
                                color: _connected
                                    ? const Color(0xFF00E676).withOpacity(0.8)
                                    : Colors.white.withOpacity(0.45),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Main content ──
                if (_loading)
                  _buildLoadingState(cs)
                else if (_error.isNotEmpty)
                  _buildErrorState(theme, cs)
                else if (_isReconnecting)
                  _buildReconnectingState(theme, cs)
                else if (_space == null)
                  _buildNoSpaceState(theme, cs, l10n)
                else
                  _buildRoom(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme cs) {
    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: cs.primary),
          const SizedBox(height: 16),
          Text(
            'Connecting to space...',
            style: TextStyle(color: Colors.white.withOpacity(0.50), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, ColorScheme cs) {
    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orangeAccent.withOpacity(0.12),
            ),
            child: const Icon(Icons.wifi_off_rounded, color: Colors.orangeAccent, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Connection Issue',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            _error,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(14),
                    child: Ink(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: Center(
                        child: Text('Go Back', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() { _error = ''; _reconnectAttempts = 0; });
                      _connectAudio();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Ink(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.75)]),
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReconnectingState(ThemeData theme, ColorScheme cs) {
    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: Colors.orangeAccent,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Reconnecting...',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Attempt $_reconnectAttempts of $_maxReconnectAttempts',
            style: TextStyle(color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Please wait while we restore your connection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.40), fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 18),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _reconnectTimer?.cancel();
                setState(() { _isReconnecting = false; _reconnectAttempts = 0; });
                unawaited(_disconnectAudio());
              },
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Center(
                  child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSpaceState(ThemeData theme, ColorScheme cs, AppLocalizations l10n) {
    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary.withOpacity(0.25), cs.primary.withOpacity(0.08)],
              ),
            ),
            child: Icon(Icons.spatial_audio_off_rounded, color: cs.primary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'No Active Space',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr('league_space_no_active_space'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.50), fontWeight: FontWeight.w600, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildRoom(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final space = _space!;

    _ensureDisplayNameLoaded(space.hostUserId);

    final isLive = _isLive;

    return Column(
      children: [
        // ── Space info card ──
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isLive ? Icons.graphic_eq_rounded : Icons.spatial_audio_off_rounded,
                    color: isLive ? cs.primary : Colors.white.withOpacity(0.4),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      space.title ?? l10n.tr('league_space_default_title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _LiveBadge(isLive: isLive, l10n: l10n),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _UserThumb(url: _avatarUrl(space.hostUserId), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n.tr('league_space_host_prefix')}${_displayName(space.hostUserId)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.50),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Controls card ──
        Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Connect / Mic buttons
              Row(
                children: [
                  Expanded(
                    child: _SpaceActionButton(
                      icon: _joiningAudio ? null : (_connected ? Icons.call_end_rounded : Icons.headset_mic_rounded),
                      label: _connected ? l10n.tr('league_space_leave_audio') : l10n.tr('league_space_join_audio'),
                      isLoading: _joiningAudio,
                      color: _connected ? cs.error : cs.primary,
                      onPressed: _joiningAudio
                          ? null
                          : _connected
                              ? () async { await _disconnectAudio(); if (mounted) setState(() {}); }
                              : _connectAudio,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SpaceActionButton(
                      icon: _micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                      label: _micEnabled ? l10n.tr('league_space_mic_on') : l10n.tr('league_space_mic_off'),
                      color: _canToggleMic ? cs.primary : Colors.white.withOpacity(0.3),
                      outlined: true,
                      onPressed: _canToggleMic ? _toggleMic : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Status text
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _connected
                      ? (_isHost
                          ? l10n.tr('league_space_connected_as_host')
                          : (_isSpeakerApproved
                              ? (_speakerMutedByHost
                                  ? l10n.tr('league_space_connected_as_speaker_muted_by_host')
                                  : l10n.tr('league_space_connected_as_speaker'))
                              : l10n.tr('league_space_connected_as_listener')))
                      : l10n.tr('league_space_not_connected'),
                  style: TextStyle(
                    color: _connected ? const Color(0xFF00E676).withOpacity(0.7) : Colors.white.withOpacity(0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Request to speak (non-host)
              if (!_isHost) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SpaceActionButton(
                        icon: Icons.record_voice_over_rounded,
                        label: _isSpeakerApproved
                            ? l10n.tr('league_space_you_are_speaker')
                            : (_myRequestStatus == 'pending'
                                ? l10n.tr('league_space_request_pending')
                                : l10n.tr('league_space_request_to_speak')),
                        color: cs.primary,
                        onPressed: (isLive && !_isSpeakerApproved && _myRequestStatus != 'pending')
                            ? _requestToSpeak
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _SpaceActionButton(
                      icon: Icons.close_rounded,
                      label: l10n.tr('common_cancel'),
                      color: Colors.white.withOpacity(0.5),
                      outlined: true,
                      onPressed: (_myRequestStatus == 'pending') ? _withdrawRequest : null,
                    ),
                  ],
                ),
                if (_myRequestStatus == 'denied') ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.tr('league_space_request_denied'),
                    style: TextStyle(color: Colors.orangeAccent.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ],
          ),
        ),

        // ── Host panel ──
        if (_isHost) ...[
          const SizedBox(height: 12),
          Glass(
            borderRadius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      l10n.tr('league_space_host_panel_title'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Requests section
                Text(
                  l10n.tr('league_space_requests_title'),
                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _requestsCol.where('status', isEqualTo: 'pending').snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _InlineErrorCard(message: _friendlyConnectionError(snap.error!));
                    }
                    if (!snap.hasData) return const SizedBox.shrink();
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          l10n.tr('league_space_no_pending_requests'),
                          style: TextStyle(color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      );
                    }
                    return Column(
                      children: docs.map((doc) {
                        final d = doc.data();
                        final userId = (d['userId'] ?? doc.id).toString();
                        _ensureDisplayNameLoaded(userId);
                        return _RequestTile(
                          name: _displayName(userId),
                          shortUid: _shortUid(userId),
                          avatarUrl: _avatarUrl(userId),
                          onApprove: () => _approveRequest(userId),
                          onDeny: () => _denyRequest(userId),
                          l10n: l10n,
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 14),
                Divider(color: Colors.white.withOpacity(0.06)),
                const SizedBox(height: 10),

                // Speakers section
                Text(
                  l10n.tr('league_space_speakers_title'),
                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _speakersCol.orderBy('approvedAtMs', descending: false).snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _InlineErrorCard(message: _friendlyConnectionError(snap.error!));
                    }
                    if (!snap.hasData) return const SizedBox.shrink();
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          l10n.tr('league_space_no_speakers_yet'),
                          style: TextStyle(color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      );
                    }
                    return Column(
                      children: docs.map((doc) {
                        final d = doc.data();
                        final userId = (d['userId'] ?? doc.id).toString();
                        final muted = d['muted'] == true;
                        _ensureDisplayNameLoaded(userId);
                        return _SpeakerTile(
                          name: _displayName(userId),
                          shortUid: _shortUid(userId),
                          avatarUrl: _avatarUrl(userId),
                          muted: muted,
                          onToggleMute: () => _toggleMuteSpeaker(userId, !muted),
                          onRemove: () => _removeSpeaker(userId),
                          l10n: l10n,
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Live Badge
// ─────────────────────────────────────────────
class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.isLive, required this.l10n});
  final bool isLive;
  final AppLocalizations l10n;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.isLive) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_LiveBadge old) {
    super.didUpdateWidget(old);
    if (widget.isLive && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    else if (!widget.isLive && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.isLive ? cs.error : Colors.white.withOpacity(0.4);

    return AnimatedBuilder(
      listenable: _pulse,
      builder: (context, child) {
        final opacity = widget.isLive ? 0.7 + (_pulse.value * 0.3) : 1.0;
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isLive) ...[
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
              const SizedBox(width: 5),
            ],
            Text(
              widget.isLive ? widget.l10n.tr('league_space_live_badge') : widget.l10n.tr('league_space_ended_badge'),
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Space Action Button
// ─────────────────────────────────────────────
class _SpaceActionButton extends StatelessWidget {
  const _SpaceActionButton({
    this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
    this.isLoading = false,
    this.onPressed,
  });

  final IconData? icon;
  final String label;
  final Color color;
  final bool outlined;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final effectiveColor = disabled ? color.withOpacity(0.4) : color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: outlined ? Colors.transparent : effectiveColor.withOpacity(0.12),
            border: Border.all(color: effectiveColor.withOpacity(outlined ? 0.30 : 0.20)),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: effectiveColor))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[Icon(icon, size: 18, color: effectiveColor), const SizedBox(width: 6)],
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: effectiveColor, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Inline Error Card (replaces red text)
// ─────────────────────────────────────────────
class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orangeAccent.withOpacity(0.7), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.orangeAccent.withOpacity(0.8), fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Request Tile
// ─────────────────────────────────────────────
class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.name,
    required this.shortUid,
    required this.avatarUrl,
    required this.onApprove,
    required this.onDeny,
    required this.l10n,
  });

  final String name;
  final String shortUid;
  final String avatarUrl;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          _UserThumb(url: avatarUrl, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                Text(shortUid, style: TextStyle(color: Colors.white.withOpacity(0.40), fontSize: 11)),
              ],
            ),
          ),
          _SmallActionBtn(
            icon: Icons.close_rounded,
            color: Colors.redAccent,
            onTap: onDeny,
          ),
          const SizedBox(width: 6),
          _SmallActionBtn(
            icon: Icons.check_rounded,
            color: cs.primary,
            onTap: onApprove,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Speaker Tile
// ─────────────────────────────────────────────
class _SpeakerTile extends StatelessWidget {
  const _SpeakerTile({
    required this.name,
    required this.shortUid,
    required this.avatarUrl,
    required this.muted,
    required this.onToggleMute,
    required this.onRemove,
    required this.l10n,
  });

  final String name;
  final String shortUid;
  final String avatarUrl;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onRemove;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          _UserThumb(url: avatarUrl, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                Row(
                  children: [
                    Text(shortUid, style: TextStyle(color: Colors.white.withOpacity(0.40), fontSize: 11)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: muted ? Colors.orangeAccent.withOpacity(0.12) : const Color(0xFF00E676).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        muted ? l10n.tr('league_space_muted') : l10n.tr('league_space_unmuted'),
                        style: TextStyle(
                          color: muted ? Colors.orangeAccent : const Color(0xFF00E676),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SmallActionBtn(
            icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: muted ? Colors.orangeAccent : const Color(0xFF00E676),
            onTap: onToggleMute,
          ),
          const SizedBox(width: 6),
          _SmallActionBtn(
            icon: Icons.person_remove_rounded,
            color: Colors.redAccent,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Small Action Button
// ─────────────────────────────────────────────
class _SmallActionBtn extends StatelessWidget {
  const _SmallActionBtn({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// User Thumbnail
// ─────────────────────────────────────────────
class _UserThumb extends StatelessWidget {
  const _UserThumb({required this.url, required this.size});
  final String url;
  final double size;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);
    final px = (size * 3).clamp(48, 120).toInt();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary.withOpacity(0.18), cs.primary.withOpacity(0.06)],
        ),
        border: Border.all(color: cs.primary.withOpacity(0.18)),
      ),
      child: ClipOval(
        child: has
            ? Image.network(
                raw,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: px,
                cacheHeight: px,
                errorBuilder: (_, __, ___) => Icon(Icons.person, size: size * 0.60, color: Colors.white.withOpacity(0.5)),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(Icons.person, size: size * 0.60, color: Colors.white.withOpacity(0.5));
                },
              )
            : Icon(Icons.person, size: size * 0.60, color: Colors.white.withOpacity(0.5)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AnimatedBuilder helper
// ─────────────────────────────────────────────
class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  Animation<dynamic> get animation => listenable as Animation<dynamic>;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => builder(context, child);
}
