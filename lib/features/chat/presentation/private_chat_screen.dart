// lib/features/chat/presentation/private_chat_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../verification/presentation/widgets/verification_badge_widget.dart';
import '../data/private_chat_repository.dart';
import '../models/private_message.dart';

class PrivateChatScreen extends StatefulWidget {
  const PrivateChatScreen({
    super.key,
    required this.threadId,
    required this.otherUserName,
    this.otherUserId,
  });

  final String threadId;
  final String otherUserName;
  final String? otherUserId;

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final PrivateChatRepository _repo = PrivateChatRepository();
  final TextEditingController _input = TextEditingController();
  bool _sending = false;

  // ── Voice recording state (mirrors LeagueChatScreen's pattern) ──────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isVoiceSending = false;
  bool _recordingPermissionDenied = false;
  String? _recordingPath;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;

  // ── Voice playback state ─────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  String? _playingMessageId;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;

  bool _busyWithAttachment = false;

  @override
  void initState() {
    super.initState();
    _wirePlayer();
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

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    _recorder.dispose();
    _input.dispose();
    super.dispose();
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await _repo.sendTextMessage(threadId: widget.threadId, text: text);
      _input.clear();
    } catch (e) {
      _toastErr(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_busyWithAttachment || _isRecording) return;

    setState(() => _busyWithAttachment = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final pick = await SafeImagePicker.pickImage();
      if (pick.wasCancelled) {
        if (mounted) setState(() => _busyWithAttachment = false);
        return;
      }
      if (!pick.isSuccess) {
        if (mounted) setState(() => _busyWithAttachment = false);
        _toast((pick.errorMessage ?? 'Could not pick image.').trim(), error: true);
        return;
      }

      final file = pick.file!;
      final url = await _repo.uploadImage(threadId: widget.threadId, file: file);
      await _repo.sendImageMessage(threadId: widget.threadId, imageUrl: url);

      if (mounted) setState(() => _busyWithAttachment = false);
    } catch (e) {
      if (mounted) setState(() => _busyWithAttachment = false);
      _toastErr(e);
    }
  }

  Future<void> _startRecording() async {
    if (_busyWithAttachment || _isVoiceSending || _isRecording) return;

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
      final outPath = p.join(tmp, 'private_chat_${widget.threadId}_$nowMs.m4a');

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
    if (_isVoiceSending || !_isRecording) return;

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

      final voiceUrl = await _repo.uploadVoice(
        threadId: widget.threadId,
        file: PlatformFile(
          name: '$nowMs.m4a',
          path: finalPath,
          size: await file.length(),
        ),
      );

      await _repo.sendVoiceMessage(threadId: widget.threadId, voiceUrl: voiceUrl);

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

  bool _isPlayingFor(String messageId) => _playingMessageId == messageId && _playing;

  Future<void> _toggleVoice(PrivateMessage msg) async {
    final url = msg.voiceUrl.trim();
    if (url.isEmpty) return;

    try {
      if (_playingMessageId == msg.id) {
        if (_player.playing) {
          await _player.pause();
        } else {
          await _player.play();
        }
        return;
      }

      await _player.stop();
      setState(() {
        _playingMessageId = msg.id;
        _pos = Duration.zero;
        _dur = Duration.zero;
      });

      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      _toastErr(e);
    }
  }

  Widget _buildRecordingBar(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.cardColor(brightness),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder(brightness)),
        ),
        child: Row(
          children: [
            Icon(Icons.mic, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Recording… ${_recordingElapsed()}',
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
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

  Widget _buildImageBubble(BuildContext context, PrivateMessage m, bool isMe) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
          maxHeight: 260,
        ),
        child: Image.network(
          m.imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 160,
            height: 160,
            color: Colors.black12,
            child: const Icon(Icons.broken_image_outlined),
          ),
          loadingBuilder: (context, child, event) {
            if (event == null) return child;
            return const SizedBox(
              width: 160,
              height: 160,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVoiceBubble(BuildContext context, PrivateMessage m, bool isMe, Brightness brightness) {
    final isPlaying = _isPlayingFor(m.id);
    final progress = _progressFor(m.id);
    final posLabel = _playingMessageId == m.id ? _fmt(_pos) : '00:00';
    final durLabel = _playingMessageId == m.id ? _fmt(_dur) : '';

    final fg = isMe ? AppTheme.darkText : AppTheme.primaryText(brightness);

    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => _toggleVoice(m),
            borderRadius: BorderRadius.circular(999),
            child: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: fg,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: fg.withOpacity(0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  durLabel.isEmpty ? 'Voice message' : '$posLabel / $durLabel',
                  style: TextStyle(
                    color: fg.withOpacity(0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final selfUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    return GlassScaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.otherUserName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.otherUserId != null && widget.otherUserId!.trim().isNotEmpty) ...[
              const SizedBox(width: 4),
              VerificationBadgeWidget(
                userId: widget.otherUserId!.trim(),
                size: 20,
              ),
            ],
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<PrivateMessage>>(
                stream: _repo.watchMessages(widget.threadId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final messages = snap.data!; // already newest-first

                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'Say hello 👋',
                        style: TextStyle(color: AppTheme.secondaryText(brightness)),
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      final isMe = m.senderId == selfUid;

                      Widget content;
                      switch (m.type) {
                        case PrivateMessageType.image:
                          content = _buildImageBubble(context, m, isMe);
                          break;
                        case PrivateMessageType.voice:
                          content = _buildVoiceBubble(context, m, isMe, brightness);
                          break;
                        case PrivateMessageType.text:
                          content = Text(
                            m.text,
                            style: TextStyle(
                              color: isMe
                                  ? AppTheme.darkText
                                  : AppTheme.primaryText(brightness),
                              fontWeight: FontWeight.w600,
                            ),
                          );
                          break;
                      }

                      final isBubbleWithOwnBackground =
                          m.type == PrivateMessageType.image;

                      return Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: isBubbleWithOwnBackground
                              ? EdgeInsets.zero
                              : const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: isBubbleWithOwnBackground
                              ? null
                              : BoxDecoration(
                                  color: isMe
                                      ? AppTheme.limeAccent
                                      : AppTheme.cardColor(brightness),
                                  borderRadius: BorderRadius.circular(16),
                                  border: isMe
                                      ? null
                                      : Border.all(
                                          color: AppTheme.cardBorder(brightness)),
                                ),
                          child: content,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_isRecording) _buildRecordingBar(context),
            if (!_isRecording)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Send photo',
                      onPressed: _busyWithAttachment ? null : _pickAndSendImage,
                      icon: _busyWithAttachment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined),
                    ),
                    IconButton(
                      tooltip: _recordingPermissionDenied
                          ? 'Microphone permission required'
                          : 'Record voice message',
                      onPressed: (_busyWithAttachment || _isVoiceSending)
                          ? null
                          : _startRecording,
                      icon: const Icon(Icons.mic_none_rounded),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(hintText: 'Message…'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}