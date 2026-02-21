import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/chat_repository.dart';
import '../models/chat_message.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/pinned_message_bar.dart';

class LeagueChatScreen extends StatefulWidget {
  final String leagueId;

  /// Pass the organizerUid of the league so we can check moderation rights.
  final String? organizerUid;

  const LeagueChatScreen({
    super.key,
    required this.leagueId,
    this.organizerUid,
  });

  @override
  State<LeagueChatScreen> createState() => _LeagueChatScreenState();
}

class _LeagueChatScreenState extends State<LeagueChatScreen> {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // messageId -> key for scroll-to
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  final ValueNotifier<String?> _selectedMessageId = ValueNotifier<String?>(null);

  bool _sending = false;
  bool _codeMode = false;
  bool _identityResolved = false;
  String _resolvedName = '';
  String _resolvedPhoto = '';

  // ===== League permission resolution (owner/organizer) =====
  bool _leagueOwnerOrOrganizer = false;
  bool _leaguePermsResolved = false;

  // ===== Voice recording =====
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isVoiceSending = false;
  bool _recordingPermissionDenied = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;

  // ===== Voice playback (single shared player) =====
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  String? _playingMessageId;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  bool get _isSuperAdmin => _user.uid.trim() == _superAdminUid;

  bool get _isSelecting => (_selectedMessageId.value ?? '').trim().isNotEmpty;

  bool get _isOrganizerFromParam =>
      widget.organizerUid != null &&
      widget.organizerUid!.trim().isNotEmpty &&
      widget.organizerUid!.trim() == _user.uid.trim();

  bool get _canModerateLeague =>
      _isSuperAdmin || _isOrganizerFromParam || (_leaguePermsResolved && _leagueOwnerOrOrganizer);

  @override
  void initState() {
    super.initState();
    _resolveIdentity();
    _resolveLeaguePermissions();
    _wirePlayer();
  }

  Future<void> _resolveLeaguePermissions() async {
    // Safe, one-time fetch; avoids blocking moderators when organizerUid param wasn't supplied.
    try {
      final snap = await FirebaseFirestore.instance.collection('leagues').doc(widget.leagueId).get();
      final data = snap.data() ?? <String, dynamic>{};

      bool isOwnerOrOrganizer = false;
      final uid = _user.uid.trim();

      // Match common fields used in rules
      final organizerUid = (data['organizerUid'] as String? ?? '').trim();
      final ownerUid = (data['ownerUid'] as String? ?? '').trim();
      final organizerUserId = (data['organizerUserId'] as String? ?? '').trim();
      final ownerId = (data['ownerId'] as String? ?? '').trim();

      if (organizerUid == uid || ownerUid == uid || organizerUserId == uid || ownerId == uid) {
        isOwnerOrOrganizer = true;
      }

      if (!mounted) return;
      setState(() {
        _leagueOwnerOrOrganizer = isOwnerOrOrganizer;
        _leaguePermsResolved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leagueOwnerOrOrganizer = false;
        _leaguePermsResolved = true;
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

  // ===== Permissions =====

  bool _canDeleteMessage(ChatMessage msg) {
    if (_canModerateLeague) return true;
    return _user.uid.trim() == msg.senderId.trim();
  }

  bool _canPinMessage(ChatMessage msg) {
    // League: organizer/admin only (no normal users).
    return _canModerateLeague;
  }

  // ===== Send text/image (existing) =====

  Future<void> _sendText() async {
    if (_isSelecting) return;

    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      await _repo.sendLeagueMessage(
        leagueId: widget.leagueId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: _codeMode ? ChatMessageType.code : ChatMessageType.text,
        text: raw,
      );

      _textCtrl.clear();
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_sending || _isSelecting) return;

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final pick = await SafeImagePicker.pickImage();
      if (pick.wasCancelled) {
        if (mounted) setState(() => _sending = false);
        return;
      }
      if (!pick.isSuccess) {
        if (mounted) setState(() => _sending = false);
        _toast((pick.errorMessage ?? 'Could not pick image.').trim(), error: true);
        return;
      }

      final file = pick.file!;
      final url = await _repo.uploadLeagueChatImage(
        leagueId: widget.leagueId,
        file: file,
      );

      await _repo.sendLeagueMessage(
        leagueId: widget.leagueId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: ChatMessageType.image,
        text: _textCtrl.text.trim(),
        imageUrl: url,
      );

      _textCtrl.clear();
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  // ===== Voice record/cancel/send =====

  Future<void> _startRecording() async {
    if (_sending || _isVoiceSending || _isRecording || _isSelecting) return;

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

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
      final outPath = p.join(tmp, 'chat_voice_${widget.leagueId}_$nowMs.m4a');

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
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
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
    if (_isVoiceSending || !_isRecording || _isSelecting) return;

    final path = (_recordingPath ?? '').trim();
    if (path.isEmpty) return;

    setState(() => _isVoiceSending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final stoppedPath = (await _recorder.stop())?.trim();
      final finalPath = (stoppedPath?.isNotEmpty == true ? stoppedPath! : path);

      _recordingTicker?.cancel();
      _recordingTicker = null;

      final file = File(finalPath);
      if (!await file.exists()) throw StateError('Recording not found. Try again.');

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final voiceUrl = await _repo.uploadLeagueChatVoice(
        leagueId: widget.leagueId,
        file: PlatformFile(
          name: '$nowMs.m4a',
          path: finalPath,
          size: await file.length(),
        ),
      );

      await _repo.sendLeagueMessage(
        leagueId: widget.leagueId,
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: ChatMessageType.voice,
        text: _textCtrl.text.trim(),
        voiceUrl: voiceUrl,
      );

      _textCtrl.clear();

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

  // ===== Voice playback =====
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
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _repo.softDeleteLeagueMessage(
        leagueId: widget.leagueId,
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
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _repo.pinLeagueMessage(
        leagueId: widget.leagueId,
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

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    _recorder.dispose();
    _scrollCtrl.dispose();
    _selectedMessageId.dispose();
    _textCtrl.dispose();
    super.dispose();
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
    return ValueListenableBuilder<String?>(
      valueListenable: _selectedMessageId,
      builder: (context, selectedId, _) {
        final selecting = (selectedId ?? '').trim().isNotEmpty;

        if (!selecting) {
          return AppBar(
            title: const Text('League Chat'),
            backgroundColor: Colors.transparent,
            elevation: 0,
          );
        }

        return AppBar(
          leading: IconButton(
            tooltip: 'Cancel selection',
            onPressed: () => _selectedMessageId.value = null,
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Text('1 selected'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          body: Column(
            children: [
              StreamBuilder<ChatMessage?>(
                stream: _repo.leaguePinnedMessageStream(widget.leagueId),
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
                  stream: _repo.leagueChatStream(widget.leagueId),
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
                                Icon(Icons.lock_outline, color: theme.colorScheme.primary, size: 34),
                                const SizedBox(height: 10),
                                Text(
                                  msg,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withOpacity(0.75),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).maybePop(),
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
                            color: theme.colorScheme.onSurface.withOpacity(0.55),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }

                    // prune keys to avoid growth
                    final ids = msgs.map((e) => e.messageId).toSet();
                    _messageKeys.removeWhere((k, _) => !ids.contains(k));

                    return ValueListenableBuilder<String?>(
                      valueListenable: _selectedMessageId,
                      builder: (context, selectedId, _) {
                        final selecting = (selectedId ?? '').trim().isNotEmpty;
                        final selectedMsg = selecting
                            ? msgs.cast<ChatMessage?>().firstWhere(
                                (m) => m?.messageId == selectedId,
                                orElse: () => null,
                              )
                            : null;

                        return Stack(
                          children: [
                            ListView.builder(
                              controller: _scrollCtrl,
                              reverse: true,
                              padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                              itemCount: msgs.length,
                              itemBuilder: (_, i) {
                                final m = msgs[i];
                                final isMe = m.senderId.trim() == _user.uid.trim();
                                final key = _messageKeys.putIfAbsent(m.messageId, () => GlobalKey());

                                return KeyedSubtree(
                                  key: key,
                                  child: ChatBubble(
                                    message: m,
                                    isMe: isMe,
                                    selected: selectedId == m.messageId,
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      _selectedMessageId.value = m.messageId;
                                    },
                                    onTap: () {
                                      if (!selecting) return;
                                      _selectedMessageId.value =
                                          (selectedId == m.messageId) ? null : m.messageId;
                                    },
                                    onPlayVoice: (m.type == ChatMessageType.voice && !selecting)
                                        ? () => _toggleVoice(m)
                                        : null,
                                    isVoicePlaying: _isPlayingFor(m.messageId),
                                    voiceProgress: _progressFor(m.messageId),
                                    voicePositionLabel: _posLabelFor(m.messageId),
                                    voiceDurationLabel: _durLabelFor(m.messageId),
                                  ),
                                );
                              },
                            ),

                            if (selecting && selectedMsg != null)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: SafeArea(
                                  child: Row(
                                    children: [
                                      IconButton(
                                        tooltip: 'Copy',
                                        onPressed: () => _copySelected(selectedMsg),
                                        icon: const Icon(Icons.copy_rounded),
                                      ),
                                      if (_canDeleteMessage(selectedMsg))
                                        IconButton(
                                          tooltip: 'Delete',
                                          onPressed: () => _softDeleteSelected(selectedMsg),
                                          icon: const Icon(Icons.delete_outline_rounded),
                                        ),
                                      if (_canPinMessage(selectedMsg))
                                        IconButton(
                                          tooltip: 'Pin',
                                          onPressed: () => _pinSelected(selectedMsg),
                                          icon: const Icon(Icons.push_pin_outlined),
                                        ),
                                      const SizedBox(width: 4),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              if (_isRecording) _buildRecordingBar(context),
              ValueListenableBuilder<String?>(
                valueListenable: _selectedMessageId,
                builder: (context, selectedId, _) {
                  final selecting = (selectedId ?? '').trim().isNotEmpty;
                  return Row(
                    children: [
                      Expanded(
                        child: ChatInputBar(
                          controller: _textCtrl,
                          isSending: _sending,
                          codeMode: _codeMode,
                          enabled: !_isRecording && !selecting,
                          onToggleCodeMode: () => setState(() => _codeMode = !_codeMode),
                          onPickImage: _pickAndSendImage,
                          onSend: _sendText,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12),
                        child: Glass(
                          padding: const EdgeInsets.all(6),
                          child: IconButton(
                            tooltip: _recordingPermissionDenied
                                ? 'Microphone permission required'
                                : (_isRecording ? 'Recording…' : 'Record voice'),
                            onPressed: (_sending || _isVoiceSending || _isRecording || selecting)
                                ? null
                                : _startRecording,
                            icon: Icon(Icons.mic, color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
