import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/push_messaging_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
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

  String _workspaceName = 'Organizer Chat';
  bool _workspaceNameResolved = false;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isVoiceSending = false;
  bool _recordingPermissionDenied = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  String? _playingMessageId;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;

  bool _chatMuted = false;
  bool _chatBanned = false;
  bool _moderationResolved = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  bool get _isSuperAdmin => _user.uid.trim() == _superAdminUid;
  bool get _isSelecting => (_selectedMessageId.value ?? '').trim().isNotEmpty;
  bool get _canModerateOrganizer =>
      _isSuperAdmin || (_workspacePermsResolved && _workspaceOwnerOrStaff);

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
    _wirePlayer();
    _watchModerationState();

    PushMessagingService.instance.setActiveLeagueChat('organizer:${widget.masterLeagueId}');
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
        _workspaceName = name.isNotEmpty ? name : 'Organizer Chat';
        _workspaceNameResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workspaceName = 'Organizer Chat';
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

      final adminIds = (data['adminIds'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet() ??
          <String>{};

      final moderatorIds = (data['moderatorIds'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet() ??
          <String>{};

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

  void _wirePlayer() {
    _posSub = _player.positionStream.listen((v) {
      if (!mounted) return;
      setState(() => _pos = v);
    });
    _durSub = _player.durationStream.listen((v) {
      if (!mounted) return;
      setState(() => _dur = v ?? Duration.zero);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final isPlaying = s.playing && s.processingState != ProcessingState.completed;
      setState(() {
        _playing = isPlaying;
        if (s.processingState == ProcessingState.completed) {
          _pos = Duration.zero;
          _playing = false;
        }
      });
    });
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
    return 'Player';
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

  void _toastErr(Object e) =>
      _toast(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')), error: true);

  bool _canDeleteMessage(ChatMessage msg) {
    if (_canModerateOrganizer) return true;
    return _user.uid.trim() == msg.senderId.trim();
  }

  bool _canPinMessage(ChatMessage msg) => _canModerateOrganizer;

  String _newMessageId() =>
      FirebaseFirestore.instance.collection('_ids').doc().id;

  Future<void> _sendText() async {
    if (_chatBlocked) {
      _toast('You are banned from Organizer Chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in Organizer Chat.', error: true);
      return;
    }
    if (_isSelecting) return;

    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 4));

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
      _toast('You are banned from Organizer Chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in Organizer Chat.', error: true);
      return;
    }
    if (_sending || _isSelecting) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 4));

      final pick = await SafeImagePicker.pickImage();
      if (pick.wasCancelled) {
        if (mounted) setState(() => _sending = false);
        return;
      }
      if (!pick.isSuccess) {
        if (mounted) setState(() => _sending = false);
        _toast((pick.errorMessage ?? 'Could not pick image.').trim(),
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
      _toast('You are banned from Organizer Chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in Organizer Chat.', error: true);
      return;
    }
    if (_sending || _isVoiceSending || _isRecording || _isSelecting) return;

    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 4));

      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        if (!mounted) return;
        setState(() => _recordingPermissionDenied = true);
        _toast('Microphone permission denied', error: true);
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
      _toast('You are banned from Organizer Chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in Organizer Chat.', error: true);
      return;
    }
    if (_isVoiceSending || !_isRecording || _isSelecting) return;

    final path = (_recordingPath ?? '').trim();
    if (path.isEmpty) return;

    final reply = _replyTo.value;
    final messageId = _newMessageId();

    setState(() => _isVoiceSending = true);
    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 4));

      final stoppedPath = (await _recorder.stop())?.trim();
      final finalPath =
          (stoppedPath?.isNotEmpty == true ? stoppedPath! : path);

      _recordingTicker?.cancel();
      _recordingTicker = null;

      final file = File(finalPath);
      if (!await file.exists()) {
        throw StateError('Recording not found. Try again.');
      }

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
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

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

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  double _progressFor(String messageId) {
    if (_playingMessageId != messageId) return 0.0;
    if (_dur.inMilliseconds <= 0) return 0.0;
    return (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
  }

  String _posLabelFor(String messageId) {
    if (_playingMessageId != messageId) return '00:00';
    return _fmt(_pos);
  }

  String _durLabelFor(String messageId) {
    if (_playingMessageId != messageId) return '00:00';
    return _fmt(_dur);
  }

  bool _isPlayingFor(String messageId) {
    return _playingMessageId == messageId && _playing;
  }

  Future<void> _toggleVoice(ChatMessage msg) async {
    final url = msg.voiceUrl.trim();
    if (url.isEmpty) return;

    try {
      if (_playingMessageId == msg.messageId) {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        return;
      }

      await _player.stop();
      setState(() {
        _playingMessageId = msg.messageId;
        _pos = Duration.zero;
        _dur = Duration.zero;
      });

      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _softDeleteSelected(ChatMessage msg) async {
    if (!_canDeleteMessage(msg)) {
      _toast('You can only delete your own messages.', error: true);
      return;
    }
    if (msg.deleted) {
      _toast('Already deleted');
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 4));
      await _repo.softDeleteOrganizerMessage(
        masterLeagueId: widget.masterLeagueId,
        messageId: msg.messageId,
        deletedBy: _user.uid,
      );
      _selectedMessageId.value = null;
      _toast('Message deleted');
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _pinSelected(ChatMessage msg) async {
    if (!_canPinMessage(msg)) {
      _toast('You do not have permission to pin messages.', error: true);
      return;
    }
    if (msg.deleted) {
      _toast('Cannot pin a deleted message.', error: true);
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 4));
      await _repo.pinOrganizerMessage(
        masterLeagueId: widget.masterLeagueId,
        messageId: msg.messageId,
        pinnedBy: _user.uid,
      );
      _selectedMessageId.value = null;
      _toast('Pinned');
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _copySelected(ChatMessage msg) async {
    if (msg.deleted) {
      _toast('Nothing to copy', error: true);
      _selectedMessageId.value = null;
      return;
    }

    final txt = msg.text.trim().isNotEmpty
        ? msg.text.trim()
        : (msg.type == ChatMessageType.image
            ? msg.imageUrl.trim()
            : (msg.type == ChatMessageType.voice ? msg.voiceUrl.trim() : ''));

    if (txt.isEmpty) {
      _toast('Nothing to copy', error: true);
      _selectedMessageId.value = null;
      return;
    }

    await Clipboard.setData(ClipboardData(text: txt));
    _toast('Copied');
    _selectedMessageId.value = null;
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) {
      _toast('Message not loaded yet');
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
                'Recording… ${_recordingElapsed()}',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _isVoiceSending ? null : _cancelRecording,
              child: const Text('Cancel'),
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
                  : const Text('Send'),
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
              title: const Text('Organizer Chat'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            );
          }

          final selectedMsg =
              (selectedId != null) ? _msgById[selectedId] : null;

          return AppBar(
            leading: IconButton(
              tooltip: 'Cancel selection',
              onPressed: () => _selectedMessageId.value = null,
              icon: const Icon(Icons.close_rounded),
            ),
            title: const Text('1 selected'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: 'Copy',
                onPressed: selectedMsg == null ? null : () => _copySelected(selectedMsg),
                icon: const Icon(Icons.copy_rounded),
              ),
              if (selectedMsg != null && _canDeleteMessage(selectedMsg))
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _softDeleteSelected(selectedMsg),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              if (selectedMsg != null && _canPinMessage(selectedMsg))
                IconButton(
                  tooltip: 'Pin',
                  onPressed: () => _pinSelected(selectedMsg),
                  icon: const Icon(Icons.push_pin_outlined),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    PushMessagingService.instance.setActiveLeagueChat(null);
    _recordingTicker?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
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
              child: Column(
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
                                color:
                                    theme.colorScheme.primary.withOpacity(0.35),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _workspaceNameResolved
                                      ? _workspaceName
                                      : 'Organizer Chat',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'General community chat across this organizer’s competitions',
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
                            onPressed: () => context
                                .push('/master-leagues/${widget.masterLeagueId}'),
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text(
                              'Workspace',
                              style: TextStyle(fontWeight: FontWeight.w900),
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
                                'You are banned from Organizer Chat. You can no longer send messages here.',
                                style: theme.textTheme.bodySmall?.copyWith(
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
                                'You are muted in Organizer Chat. You can read messages but cannot send new ones.',
                                style: theme.textTheme.bodySmall?.copyWith(
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
                    stream: _repo.organizerPinnedMessageStream(widget.masterLeagueId),
                    builder: (context, snap) {
                      final pinned = snap.data;
                      if (pinned == null) return const SizedBox.shrink();
                      return PinnedMessageBar(
                        message: pinned,
                        onTap: () => _scrollToMessage(pinned.messageId),
                      );
                    },
                  ),
                  Expanded(
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: _repo.organizerChatStream(widget.masterLeagueId),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          final msg = UserFriendlyError.toMessage(
                            snap.error is Object ? snap.error! : Exception('unknown'),
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
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.75),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      child: const Text('Back'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final msgs = snap.data ?? const <ChatMessage>[];
                        if (msgs.isEmpty) {
                          return Center(
                            child: Text(
                              'No messages yet',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }

                        _msgById = {for (final m in msgs) m.messageId: m};

                        final ids = msgs.map((e) => e.messageId).toSet();
                        _messageKeys.removeWhere((k, _) => !ids.contains(k));

                        return ListView.builder(
                          controller: _scrollCtrl,
                          reverse: true,
                          padding:
                              const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final m = msgs[i];
                            final isMe =
                                m.senderId.trim() == _user.uid.trim();
                            final key = _messageKeys.putIfAbsent(
                                m.messageId, () => GlobalKey());

                            return ValueListenableBuilder<String?>(
                              valueListenable: _selectedMessageId,
                              builder: (context, selectedId, _) {
                                final selecting =
                                    (selectedId ?? '').trim().isNotEmpty;

                                return KeyedSubtree(
                                  key: key,
                                  child: ChatBubble(
                                    message: m,
                                    isMe: isMe,
                                    selected: selectedId == m.messageId,
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      _replyTo.value = null;
                                      _selectedMessageId.value = m.messageId;
                                    },
                                    onTap: () {
                                      if (!selecting) return;
                                      _selectedMessageId.value =
                                          (selectedId == m.messageId)
                                              ? null
                                              : m.messageId;
                                    },
                                    onSwipeReply:
                                        selecting ? null : () => _replyTo.value = m,
                                    onPlayVoice:
                                        (m.type == ChatMessageType.voice &&
                                                !selecting)
                                            ? () => _toggleVoice(m)
                                            : null,
                                    isVoicePlaying: _isPlayingFor(m.messageId),
                                    voiceProgress: _progressFor(m.messageId),
                                    voicePositionLabel:
                                        _posLabelFor(m.messageId),
                                    voiceDurationLabel:
                                        _durLabelFor(m.messageId),
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
                      animation: Listenable.merge([_selectedMessageId, _replyTo]),
                      builder: (context, _) {
                        final selecting =
                            (_selectedMessageId.value ?? '').trim().isNotEmpty;
                        final reply = _replyTo.value;

                        return ChatInputBar(
                          controller: _textCtrl,
                          isSending: _sending,
                          codeMode: _codeMode,
                          onToggleCodeMode: () =>
                              setState(() => _codeMode = !_codeMode),
                          enabled: !_isRecording &&
                              !selecting &&
                              !_chatReadOnly &&
                              !_chatBlocked,
                          onPickImage: _chatReadOnly ? null : _pickAndSendImage,
                          onSend: _chatReadOnly ? null : _sendText,
                          onRecordVoice: (_sending ||
                                  _isVoiceSending ||
                                  _isRecording ||
                                  selecting ||
                                  _chatReadOnly)
                              ? null
                              : _startRecording,
                          voiceTooltip: _recordingPermissionDenied
                              ? 'Microphone permission required'
                              : 'Record voice',
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
