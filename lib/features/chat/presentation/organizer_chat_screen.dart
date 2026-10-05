//OrganizerChatScreen
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/push_messaging_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/services/supabase_edge_notifications_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../leagues/data/leagues_repository_local.dart';
import '../../master_leagues/data/master_leagues_repository_firebase.dart';
import '../../moderation/models/user_report.dart';
import '../../moderation/presentation/report_sheet.dart';
import '../../profile/data/team_profile_repository.dart';
import '../data/chat_repository.dart';
import '../models/chat_message.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/pinned_message_bar.dart';

class OrganizerChatScreen extends StatefulWidget {
  const OrganizerChatScreen({
    super.key,
    required this.masterLeagueId,
  });

  final String masterLeagueId;

  @override
  State<OrganizerChatScreen> createState() => _OrganizerChatScreenState();
}

class _OrganizerChatScreenState extends State<OrganizerChatScreen> {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  Map<String, ChatMessage> _msgById = <String, ChatMessage>{};

  final ValueNotifier<String?> _selectedMessageId = ValueNotifier<String?>(null);
  final ValueNotifier<ChatMessage?> _replyTo = ValueNotifier<ChatMessage?>(null);

  bool _sending = false;
  bool _codeMode = false;
  bool _identityResolved = false;
  String _resolvedName = '';
  String _resolvedPhoto = '';

  bool _workspaceOwnerOrStaff = false;
  bool _workspacePermsResolved = false;

  bool _chatAccessResolved = false;
  bool _chatAccessAllowed = false;
  String _chatAccessReason =
      'Organizer chat is only available if you follow this organizer or joined one of their competitions.';

  String _workspaceName = 'Organizer Chat';
  bool _workspaceNameResolved = false;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isVoiceSending = false;
  bool _recordingPermissionDenied = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;

  bool _chatMuted = false;
  bool _chatBanned = false;
  bool _moderationResolved = false;

  Set<String> _blockedUserIds = <String>{};

  User get _user => FirebaseAuth.instance.currentUser!;

  bool get _isSelecting => (_selectedMessageId.value ?? '').trim().isNotEmpty;
  bool get _canModerateOrganizer =>
      _workspacePermsResolved && _workspaceOwnerOrStaff;

  bool get _chatReadOnly => _chatMuted && !_canModerateOrganizer;
  bool get _chatBlocked => _chatBanned && !_canModerateOrganizer;

  DocumentReference<Map<String, dynamic>> get _moderationDoc => FirebaseFirestore
      .instance
      .collection('master_leagues')
      .doc(widget.masterLeagueId)
      .collection('memberModeration')
      .doc(_user.uid.trim());

  @override
  void initState() {
    super.initState();
    _resolveIdentity();
    _resolveWorkspacePermissions();
    _resolveWorkspaceName();
    _resolveChatEligibility();
    _watchModerationState();
    _loadBlockedUserIds();

    PushMessagingService.instance
        .subscribeToOrganizerChatTopic(widget.masterLeagueId);
    PushMessagingService.instance
        .setActiveLeagueChat('organizer:${widget.masterLeagueId}');
  }

  Future<void> _loadBlockedUserIds() async {
    final ids = await TeamProfileRepository().fetchBlockedEitherWayUserIds();
    if (!mounted) return;
    setState(() => _blockedUserIds = ids);
  }

  Future<void> _resolveChatEligibility() async {
    final uid = _user.uid.trim();
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _chatAccessResolved = true;
        _chatAccessAllowed = false;
        _chatAccessReason = context.l10n.tr('organizer_chat_sign_in_required');
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('master_leagues')
          .doc(widget.masterLeagueId)
          .get();

      final data = doc.data() ?? <String, dynamic>{};
      final ownerId = (data['ownerId'] as String? ?? '').trim();

      if (ownerId == uid) {
        if (!mounted) return;
        setState(() {
          _chatAccessResolved = true;
          _chatAccessAllowed = true;
        });
        return;
      }

      final rolesMap = (data['roles'] as Map?)
              ?.map((k, v) => MapEntry(
                  k.toString().trim(), v.toString().trim().toLowerCase())) ??
          <String, String>{};

      final adminIds = rolesMap.entries
          .where((e) => e.value == 'admin')
          .map((e) => e.key)
          .where((e) => e.isNotEmpty)
          .toSet();

      final moderatorIds = rolesMap.entries
          .where((e) => e.value == 'moderator')
          .map((e) => e.key)
          .where((e) => e.isNotEmpty)
          .toSet();

      final memberIds = (data['memberIds'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet() ??
          <String>{};

      if (adminIds.contains(uid) ||
          moderatorIds.contains(uid) ||
          memberIds.contains(uid)) {
        if (!mounted) return;
        setState(() {
          _chatAccessResolved = true;
          _chatAccessAllowed = true;
        });
        return;
      }

      final repo = MasterLeaguesRepositoryFirebase(
        firestore: FirebaseFirestore.instance,
      );

      final isFollowing = await repo.isFollowingWorkspace(widget.masterLeagueId);
      if (isFollowing) {
        if (!mounted) return;
        setState(() {
          _chatAccessResolved = true;
          _chatAccessAllowed = true;
        });
        return;
      }

      final prefs = await PreferencesService.create();
      final localRepo = LocalLeaguesRepository(prefs);

      final memberships = await localRepo.listMemberships();
      final joinedLeagueIds = memberships
          .where((m) => m.userId.trim() == uid)
          .map((m) => m.leagueId.trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      if (joinedLeagueIds.isNotEmpty) {
        final leaguesSnap = await FirebaseFirestore.instance
            .collection('leagues')
            .where('masterLeagueId', isEqualTo: widget.masterLeagueId)
            .get();

        bool hasJoinedCompetition = false;
        for (final d in leaguesSnap.docs) {
          if (joinedLeagueIds.contains(d.id.trim())) {
            hasJoinedCompetition = true;
            break;
          }
          final remoteId = (d.data()['id'] ?? '').toString().trim();
          if (remoteId.isNotEmpty && joinedLeagueIds.contains(remoteId)) {
            hasJoinedCompetition = true;
            break;
          }
        }

        if (hasJoinedCompetition) {
          if (!mounted) return;
          setState(() {
            _chatAccessResolved = true;
            _chatAccessAllowed = true;
          });
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _chatAccessResolved = true;
        _chatAccessAllowed = false;
        _chatAccessReason =
            context.l10n.tr('organizer_chat_access_denied_message');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chatAccessResolved = true;
        _chatAccessAllowed = false;
        _chatAccessReason =
            context.l10n.tr('organizer_chat_access_check_failed');
      });
    }
  }

  void _watchModerationState() {
    _moderationDoc.snapshots(includeMetadataChanges: true).listen((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _chatMuted = data['chatMuted'] == true;
        _chatBanned = data['chatBanned'] == true;
        _moderationResolved = true;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _chatMuted = false;
        _chatBanned = false;
        _moderationResolved = true;
      });
    });
  }

  Future<void> _resolveWorkspaceName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('master_leagues')
          .doc(widget.masterLeagueId)
          .get();
      final data = doc.data() ?? <String, dynamic>{};
      final name = (data['name'] ?? data['title'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _workspaceName =
            name.isNotEmpty ? name : context.l10n.tr('organizer_chat_default_title');
        _workspaceNameResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workspaceName = context.l10n.tr('organizer_chat_default_title');
        _workspaceNameResolved = true;
      });
    }
  }

  Future<void> _resolveWorkspacePermissions() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('master_leagues')
          .doc(widget.masterLeagueId)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final uid = _user.uid.trim();

      bool allowed = false;

      final ownerId = (data['ownerId'] as String? ?? '').trim();
      if (ownerId == uid && uid.isNotEmpty) {
        allowed = true;
      }

      final rolesMap = (data['roles'] as Map?)
              ?.map((k, v) => MapEntry(
                  k.toString().trim(), v.toString().trim().toLowerCase())) ??
          <String, String>{};

      final adminIds = rolesMap.entries
          .where((e) => e.value == 'admin')
          .map((e) => e.key)
          .where((e) => e.isNotEmpty)
          .toSet();

      final moderatorIds = rolesMap.entries
          .where((e) => e.value == 'moderator')
          .map((e) => e.key)
          .where((e) => e.isNotEmpty)
          .toSet();

      final memberIds = (data['memberIds'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet() ??
          <String>{};

      if (adminIds.contains(uid) ||
          moderatorIds.contains(uid) ||
          memberIds.contains(uid)) {
        allowed = true;
      }

      if (!mounted) return;
      setState(() {
        _workspaceOwnerOrStaff = allowed;
        _workspacePermsResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workspaceOwnerOrStaff = false;
        _workspacePermsResolved = true;
      });
    }
  }

  Future<void> _resolveIdentity() async {
    try {
      final result = await _repo.resolveSenderIdentity(
        uid: _user.uid,
        fallbackName: _fallbackName(),
        fallbackPhoto: _fallbackPhoto(),
      );
      if (!mounted) return;
      setState(() {
        _resolvedName = result.name;
        _resolvedPhoto = result.photo;
        _identityResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolvedName = _fallbackName();
        _resolvedPhoto = _fallbackPhoto();
        _identityResolved = true;
      });
    }
  }

  String _fallbackName() {
    final dn = (_user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final email = (_user.email ?? '').trim();
    if (email.isNotEmpty) return email.split('@').first;
    return context.l10n.tr('organizer_chat_default_player_name');
  }

  String _fallbackPhoto() => (_user.photoURL ?? '').trim();

  String _senderName() {
    if (_identityResolved && _resolvedName.isNotEmpty) return _resolvedName;
    return _fallbackName();
  }

  String _senderPhoto() {
    if (_identityResolved && _resolvedPhoto.isNotEmpty) return _resolvedPhoto;
    return _fallbackPhoto();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? cs.error : null,
        content: Text(msg),
      ),
    );
  }

  void _toastErr(Object e) => _toast(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
        error: true,
      );

  bool _canDeleteMessage(ChatMessage msg) {
    if (_canModerateOrganizer) return true;
    return _user.uid.trim() == msg.senderId.trim();
  }

  bool _canPinMessage(ChatMessage msg) => _canModerateOrganizer;

  String _newMessageId() =>
      FirebaseFirestore.instance.collection('_ids').doc().id;

  String _previewForOutgoing({
    required String type,
    required String text,
    required String imageUrl,
    required String voiceUrl,
  }) {
    final t = type.trim();
    if (t == ChatMessageType.voice || voiceUrl.trim().isNotEmpty) {
      return context.l10n.tr('league_chat_preview_voice_message');
    }
    if (t == ChatMessageType.image || imageUrl.trim().isNotEmpty) {
      return context.l10n.tr('league_chat_preview_photo');
    }
    if (t == ChatMessageType.code) return context.l10n.tr('league_chat_preview_code_snippet');
    final msg = text.trim();
    if (msg.isEmpty) return context.l10n.tr('league_chat_preview_new_message');
    return msg.length > 140 ? '${msg.substring(0, 140)}…' : msg;
  }

  Future<void> _notifyPush({
    required String messageId,
    required String preview,
  }) async {
    await SupabaseEdgeNotificationsService.instance.notifyOrganizerChatMessage(
      masterLeagueId: widget.masterLeagueId,
      workspaceName:
          _workspaceNameResolved ? _workspaceName : context.l10n.tr('organizer_chat_default_title'),
      messageId: messageId,
      senderId: _user.uid.trim(),
      senderName: _senderName().trim(),
      preview: preview.trim(),
    );
  }

  Future<void> _sendText() async {
    if (_chatBlocked) {
      _toast(context.l10n.tr('organizer_chat_banned_message'), error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast(context.l10n.tr('organizer_chat_muted_message'), error: true);
      return;
    }
    if (_isSelecting) return;

    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      await _repo.sendOrganizerMessage(
        masterLeagueId: widget.masterLeagueId,
        messageIdOverride: messageId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: _codeMode ? ChatMessageType.code : ChatMessageType.text,
        text: raw,
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

      final preview = _previewForOutgoing(
        type: ChatMessageType.text,
        text: raw,
        imageUrl: '',
        voiceUrl: '',
      );
      _notifyPush(messageId: messageId, preview: preview);

      _textCtrl.clear();
      _replyTo.value = null;

      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_chatBlocked) {
      _toast(context.l10n.tr('organizer_chat_banned_message'), error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast(context.l10n.tr('organizer_chat_muted_message'), error: true);
      return;
    }
    if (_sending || _isSelecting) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final pick = await SafeImagePicker.pickImage();
      if (pick.wasCancelled) {
        if (mounted) setState(() => _sending = false);
        return;
      }
      if (!pick.isSuccess) {
        if (mounted) setState(() => _sending = false);
        _toast(
            (pick.errorMessage ?? context.l10n.tr('organizer_chat_pick_image_failed'))
                .trim(),
            error: true);
        return;
      }

      final file = pick.file!;
      final url = await _repo.uploadOrganizerChatImage(
        masterLeagueId: widget.masterLeagueId,
        file: file,
      );

      final caption = _textCtrl.text.trim();

      await _repo.sendOrganizerMessage(
        masterLeagueId: widget.masterLeagueId,
        messageIdOverride: messageId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: ChatMessageType.image,
        text: caption,
        imageUrl: url,
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

      final preview = _previewForOutgoing(
        type: ChatMessageType.image,
        text: caption,
        imageUrl: url,
        voiceUrl: '',
      );
      _notifyPush(messageId: messageId, preview: preview);

      _textCtrl.clear();
      _replyTo.value = null;

      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  Future<void> _startRecording() async {
    if (_chatBlocked) {
      _toast(context.l10n.tr('organizer_chat_banned_message'), error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast(context.l10n.tr('organizer_chat_muted_message'), error: true);
      return;
    }
    if (_sending || _isVoiceSending || _isRecording || _isSelecting) return;

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        if (!mounted) return;
        setState(() => _recordingPermissionDenied = true);
        _toast(context.l10n.tr('organizer_chat_mic_permission_denied'), error: true);
        return;
      }
      if (!mounted) return;
      setState(() => _recordingPermissionDenied = false);

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final tmp = Directory.systemTemp.path;
      final outPath =
          p.join(tmp, 'organizer_chat_${widget.masterLeagueId}_$nowMs.m4a');

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: outPath,
      );

      _recordingTicker?.cancel();
      _recordingStartedAt = DateTime.now();
      _recordingTicker =
          Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() {});
      });

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = outPath;
      });
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTicker?.cancel();
      _recordingTicker = null;
      _recordingStartedAt = null;

      if (_isRecording) {
        await _recorder.stop();
      }

      final path = _recordingPath;
      if (path != null) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _sendRecording() async {
    if (_chatBlocked) {
      _toast(context.l10n.tr('organizer_chat_banned_message'), error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast(context.l10n.tr('organizer_chat_muted_message'), error: true);
      return;
    }
    if (_isVoiceSending || !_isRecording || _isSelecting) return;

    final path = (_recordingPath ?? '').trim();
    if (path.isEmpty) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _isVoiceSending = true);
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final stoppedPath = (await _recorder.stop())?.trim();
      final finalPath =
          (stoppedPath?.isNotEmpty == true ? stoppedPath! : path);

      _recordingTicker?.cancel();
      _recordingTicker = null;

      final file = File(finalPath);
      if (!await file.exists()) {
        throw StateError(context.l10n.tr('organizer_chat_recording_not_found'));
      }

      final recordedMs = _recordingStartedAt == null
          ? 0
          : DateTime.now().difference(_recordingStartedAt!).inMilliseconds;

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final voiceUrl = await _repo.uploadOrganizerChatVoice(
        masterLeagueId: widget.masterLeagueId,
        file: PlatformFile(
          name: '$nowMs.m4a',
          path: finalPath,
          size: await file.length(),
        ),
      );

      final caption = _textCtrl.text.trim();

      await _repo.sendOrganizerMessage(
        masterLeagueId: widget.masterLeagueId,
        messageIdOverride: messageId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: ChatMessageType.voice,
        text: caption,
        voiceUrl: voiceUrl,
        voiceDurationMs: recordedMs,
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

      final preview = _previewForOutgoing(
        type: ChatMessageType.voice,
        text: caption,
        imageUrl: '',
        voiceUrl: voiceUrl,
      );
      _notifyPush(messageId: messageId, preview: preview);

      _textCtrl.clear();
      _replyTo.value = null;

      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingStartedAt = null;
        _isVoiceSending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVoiceSending = false);
      _toastErr(e);
    }
  }

  String _recordingElapsed() {
    final started = _recordingStartedAt;
    if (!_isRecording || started == null) return '00:00';
    final d = DateTime.now().difference(started);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _softDeleteSelected(ChatMessage msg) async {
    if (!_canDeleteMessage(msg)) {
      _toast(context.l10n.tr('organizer_chat_delete_own_only'), error: true);
      return;
    }
    if (msg.deleted) {
      _toast(context.l10n.tr('organizer_chat_already_deleted'));
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      await _repo.softDeleteOrganizerMessage(
        masterLeagueId: widget.masterLeagueId,
        messageId: msg.messageId,
        deletedBy: _user.uid,
      );
      _selectedMessageId.value = null;
      _toast(context.l10n.tr('organizer_chat_message_deleted'));
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _pinSelected(ChatMessage msg) async {
    if (!_canPinMessage(msg)) {
      _toast(context.l10n.tr('organizer_chat_pin_permission_denied'), error: true);
      return;
    }
    if (msg.deleted) {
      _toast(context.l10n.tr('organizer_chat_cannot_pin_deleted'), error: true);
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      await _repo.pinOrganizerMessage(
        masterLeagueId: widget.masterLeagueId,
        messageId: msg.messageId,
        pinnedBy: _user.uid,
      );
      _selectedMessageId.value = null;
      _toast(context.l10n.tr('organizer_chat_pinned'));
    } catch (e) {
      _toastErr(e);
    }
  }

  void _reportSelected(ChatMessage msg) {
    if (_canDeleteMessage(msg)) return; // can't report your own message
    _selectedMessageId.value = null;
    showReportSheet(
      context,
      targetUserId: msg.senderId,
      targetType: ReportTargetType.message,
      contextId: msg.messageId,
      contextLocation: widget.masterLeagueId,
    );
  }

  Future<void> _copySelected(ChatMessage msg) async {
    if (msg.deleted) {
      _toast(context.l10n.tr('organizer_chat_nothing_to_copy'), error: true);
      _selectedMessageId.value = null;
      return;
    }

    final txt = msg.text.trim().isNotEmpty
        ? msg.text.trim()
        : (msg.type == ChatMessageType.image
            ? msg.imageUrl.trim()
            : (msg.type == ChatMessageType.voice ? msg.voiceUrl.trim() : ''));

    if (txt.isEmpty) {
      _toast(context.l10n.tr('organizer_chat_nothing_to_copy'), error: true);
      _selectedMessageId.value = null;
      return;
    }

    await Clipboard.setData(ClipboardData(text: txt));
    _toast(context.l10n.tr('organizer_chat_copied'));
    _selectedMessageId.value = null;
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) {
      _toast(context.l10n.tr('organizer_chat_message_not_loaded'));
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  Widget _buildRecordingBar(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.mic, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "${context.l10n.tr('organizer_chat_recording_prefix')}${_recordingElapsed()}",
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _isVoiceSending ? null : _cancelRecording,
              child: Text(context.l10n.tr('common_cancel')),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _isVoiceSending ? null : _sendRecording,
              child: _isVoiceSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.l10n.tr('organizer_chat_send')),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ValueListenableBuilder<String?>(
        valueListenable: _selectedMessageId,
        builder: (context, selectedId, _) {
          final selecting = (selectedId ?? '').trim().isNotEmpty;

          if (!selecting) {
            return AppBar(
              title: Text(context.l10n.tr('organizer_chat_default_title')),
              backgroundColor: Colors.transparent,
              elevation: 0,
            );
          }

          final selectedMsg =
              (selectedId != null) ? _msgById[selectedId] : null;

          return AppBar(
            leading: IconButton(
              tooltip: context.l10n.tr('organizer_chat_cancel_selection_tooltip'),
              onPressed: () => _selectedMessageId.value = null,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text(context.l10n.tr('organizer_chat_one_selected')),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: context.l10n.tr('common_copy'),
                onPressed:
                    selectedMsg == null ? null : () => _copySelected(selectedMsg),
                icon: const Icon(Icons.copy_rounded),
              ),
              if (selectedMsg != null && _canDeleteMessage(selectedMsg))
                IconButton(
                  tooltip: context.l10n.tr('organizer_chat_delete_tooltip'),
                  onPressed: () => _softDeleteSelected(selectedMsg),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              if (selectedMsg != null && _canPinMessage(selectedMsg))
                IconButton(
                  tooltip: context.l10n.tr('organizer_chat_pin_tooltip'),
                  onPressed: () => _pinSelected(selectedMsg),
                  icon: const Icon(Icons.push_pin_outlined),
                ),
              if (selectedMsg != null && !_canDeleteMessage(selectedMsg))
                IconButton(
                  tooltip: context.l10n.tr('moderation_report_tooltip'),
                  onPressed: () => _reportSelected(selectedMsg),
                  icon: const Icon(Icons.flag_outlined),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccessDeniedView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Glass(
          padding: const EdgeInsets.all(18),
          borderRadius: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: theme.colorScheme.primary,
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.tr('organizer_chat_locked_title'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _chatAccessReason,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.72),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () =>
                    context.push('/master-leagues/${widget.masterLeagueId}'),
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(
                  context.l10n.tr('organizer_chat_back_to_workspace'),
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    PushMessagingService.instance.setActiveLeagueChat(null);
    _recordingTicker?.cancel();
    _recorder.dispose();
    _scrollCtrl.dispose();
    _selectedMessageId.dispose();
    _replyTo.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double topBodyOffset = kToolbarHeight;

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient(theme.brightness),
      ),
      child: WillPopScope(
        onWillPop: () async {
          if (_isSelecting) {
            _selectedMessageId.value = null;
            return false;
          }
          return true;
        },
        child: GlassScaffold(
          appBar: _buildAppBar(),
          body: SafeArea(
            top: true,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: topBodyOffset),
              child: !_chatAccessResolved
                  ? const Center(child: CircularProgressIndicator())
                  : !_chatAccessAllowed
                      ? _buildAccessDeniedView(theme)
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                              child: Glass(
                                borderRadius: 18,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.06),
                                        border: Border.all(
                                          color: theme.colorScheme.primary
                                              .withOpacity(0.35),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.hub_rounded,
                                        color: theme.colorScheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _workspaceNameResolved
                                                ? _workspaceName
                                                : context.l10n.tr('organizer_chat_default_title'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            context.l10n.tr('organizer_chat_description'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.62),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => context.push(
                                          '/master-leagues/${widget.masterLeagueId}'),
                                      icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 16),
                                      label: Text(
                                        context.l10n.tr('organizer_chat_workspace_label'),
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_moderationResolved && _chatBlocked)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                child: Glass(
                                  borderRadius: 18,
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Icon(Icons.block_rounded,
                                          color: theme.colorScheme.error),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          context.l10n.tr('organizer_chat_banned_full_message'),
                                          style:
                                              theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.error,
                                            fontWeight: FontWeight.w800,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (_moderationResolved && _chatReadOnly)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                child: Glass(
                                  borderRadius: 18,
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.volume_off_rounded,
                                          color: Color(0xFFF59E0B)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          context.l10n.tr('organizer_chat_muted_full_message'),
                                          style:
                                              theme.textTheme.bodySmall?.copyWith(
                                            color: const Color(0xFFF59E0B),
                                            fontWeight: FontWeight.w800,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            StreamBuilder<ChatMessage?>(
                              stream: _repo.organizerPinnedMessageStream(
                                  widget.masterLeagueId),
                              builder: (context, snap) {
                                final pinned = snap.data;
                                if (pinned == null) return const SizedBox.shrink();
                                return PinnedMessageBar(
                                  message: pinned,
                                  onTap: () =>
                                      _scrollToMessage(pinned.messageId),
                                );
                              },
                            ),
                            Expanded(
                              child: StreamBuilder<List<ChatMessage>>(
                                stream: _repo.organizerChatStream(
                                    widget.masterLeagueId),
                                builder: (context, snap) {
                                  if (snap.hasError) {
                                    final msg = UserFriendlyError.toMessage(
                                      snap.error is Object
                                          ? snap.error!
                                          : Exception('unknown'),
                                    );

                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Glass(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.lock_outline,
                                                  color: theme.colorScheme.primary,
                                                  size: 34),
                                              const SizedBox(height: 10),
                                              Text(
                                                msg,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme.onSurface
                                                      .withOpacity(0.75),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .maybePop(),
                                                child: Text(context.l10n.tr('common_back')),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final msgs = (snap.data ?? const <ChatMessage>[])
                                      .where((m) => !_blockedUserIds.contains(m.senderId))
                                      .toList(growable: false);
                                  if (msgs.isEmpty) {
                                    return Center(
                                      child: Text(
                                        context.l10n.tr('organizer_chat_no_messages'),
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.55),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    );
                                  }

                                  _msgById = {
                                    for (final m in msgs) m.messageId: m
                                  };

                                  final ids =
                                      msgs.map((e) => e.messageId).toSet();
                                  _messageKeys.removeWhere(
                                      (k, _) => !ids.contains(k));

                                  return ListView.builder(
                                    controller: _scrollCtrl,
                                    reverse: true,
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            12, 12, 12, 12),
                                    itemCount: msgs.length,
                                    itemBuilder: (_, i) {
                                      final m = msgs[i];
                                      final isMe = m.senderId.trim() ==
                                          _user.uid.trim();
                                      final key = _messageKeys.putIfAbsent(
                                          m.messageId, () => GlobalKey());

                                      return ValueListenableBuilder<String?>(
                                        valueListenable: _selectedMessageId,
                                        builder:
                                            (context, selectedId, _) {
                                          final selecting =
                                              (selectedId ?? '')
                                                  .trim()
                                                  .isNotEmpty;

                                          return KeyedSubtree(
                                            key: key,
                                            child: ChatBubble(
                                              message: m,
                                              isMe: isMe,
                                              selected:
                                                  selectedId == m.messageId,
                                              messageRef: _repo.organizerMessageRef(
                                                widget.masterLeagueId,
                                                m.messageId,
                                              ),
                                              onLongPress: () {
                                                HapticFeedback.mediumImpact();
                                                _replyTo.value = null;
                                                _selectedMessageId.value =
                                                    m.messageId;
                                              },
                                              onTap: () {
                                                if (!selecting) return;
                                                _selectedMessageId.value =
                                                    (selectedId == m.messageId)
                                                        ? null
                                                        : m.messageId;
                                              },
                                              onSwipeReply: selecting
                                                  ? null
                                                  : () => _replyTo.value = m,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            if (_isRecording) _buildRecordingBar(context),
                            if (!_chatBlocked)
                              AnimatedBuilder(
                                animation: Listenable.merge(
                                    [_selectedMessageId, _replyTo]),
                                builder: (context, _) {
                                  final selecting =
                                      (_selectedMessageId.value ?? '')
                                          .trim()
                                          .isNotEmpty;
                                  final reply = _replyTo.value;

                                  return ChatInputBar(
                                    controller: _textCtrl,
                                    isSending: _sending,
                                    codeMode: _codeMode,
                                    onToggleCodeMode: () => setState(
                                        () => _codeMode = !_codeMode),
                                    enabled: !_isRecording &&
                                        !selecting &&
                                        !_chatReadOnly &&
                                        !_chatBlocked,
                                    onPickImage: () {
                                      if (_chatReadOnly || _chatBlocked) return;
                                      _pickAndSendImage();
                                    },
                                    onSend: () {
                                      if (_chatReadOnly || _chatBlocked) return;
                                      _sendText();
                                    },
                                    onRecordVoice: (_sending ||
                                            _isVoiceSending ||
                                            _isRecording ||
                                            selecting ||
                                            _chatReadOnly)
                                        ? null
                                        : _startRecording,
                                    voiceTooltip: _recordingPermissionDenied
                                        ? context.l10n
                                            .tr('organizer_chat_mic_permission_required_tooltip')
                                        : context.l10n.tr('organizer_chat_record_voice_tooltip'),
                                    replySenderName: reply?.displaySenderName,
                                    replyPreview: reply?.replyPreview(),
                                    onCancelReply: () => _replyTo.value = null,
                                  );
                                },
                              ),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }
}
