// lib/features/chat/presentation/private_chat_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/reactions/message_reaction.dart';
import '../../../core/reactions/presentation/reaction_picker.dart';
import '../../../core/reactions/presentation/reaction_pill_bar.dart';
import '../../../core/reactions/reactions_repository.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/plan_status_service.dart';
import '../../../core/services/push_messaging_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/services/supabase_edge_notifications_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../leagues/presentation/upgrade_plan_screen.dart';
import '../../moderation/models/user_report.dart';
import '../../moderation/presentation/report_sheet.dart';
import '../../verification/presentation/widgets/verification_badge_widget.dart';
import '../data/private_chat_repository.dart';
import '../models/chat_message.dart' show ChatDeliveryStatus;
import '../models/private_message.dart';
import 'widgets/chat_image_media.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/voice_message_player.dart';
import 'widgets/voice_record_controls.dart';

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
  final UserProfileRepository _profiles = UserProfileRepository();
  final TextEditingController _input = TextEditingController();

  // Created once here rather than inline in the StreamBuilder below --
  // calling _repo.watchMessages(...) directly as a StreamBuilder's
  // `stream:` means a NEW Firestore listener is created on every
  // rebuild (and this screen has many setState() calls: recording,
  // attachments, reactions, pending messages...). StreamBuilder treats
  // each new stream instance as starting fresh, so the message list
  // flashed back to its loading spinner on nearly every interaction
  // before "reloading" moments later.
  late final Stream<List<PrivateMessage>> _messagesStream =
      _repo.watchMessages(widget.threadId);

  // The name passed via GoRoute `extra` (e.g. tapping a thread from the
  // inbox list, which always sets it) — but a notification tap or deep
  // link into `/chat/:threadId` carries no `extra` at all, so
  // app_router.dart's route falls back to the literal string 'User'.
  // Resolved for real below whenever that happens.
  late String _resolvedOtherUserName = widget.otherUserName;

  /// Optimistic messages keyed by the client-generated id used as their
  /// Firestore doc id, shown immediately on send before the write (and the
  /// realtime listener's own echo of it) confirms. Dropped once the
  /// listener delivers a doc with the same id (see the StreamBuilder
  /// below) or replaced with a [ChatDeliveryStatus.failed] copy on error.
  final Map<String, PrivateMessage> _pendingMessages = <String, PrivateMessage>{};

  // ── Voice recording state (mirrors LeagueChatScreen's pattern) ──────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isVoiceSending = false;
  bool _recordingPermissionDenied = false;
  String? _recordingPath;

  // When the CURRENTLY ACTIVE recording segment started -- null while
  // _recordingPaused (there is no active segment). _recordedMsBeforePause
  // accumulates every completed segment's duration, so pausing/resuming
  // any number of times still produces a correct total -- see
  // _pauseRecording()/_resumeRecording().
  DateTime? _recordingSegmentStartedAt;
  int _recordedMsBeforePause = 0;
  Timer? _recordingTicker;

  // Tapping the mic button starts recording immediately and the screen
  // shows persistent Cancel/Pause-or-Resume/Send controls right away --
  // _recordingPaused tracks whether audio is actively being captured right
  // now (false) or paused (true).
  bool _recordingPaused = false;

  bool _busyWithAttachment = false;

  @override
  void initState() {
    super.initState();
    // Suppresses the foreground push banner while the user is already
    // looking at this thread (mirrors LeagueChatScreen's
    // setActiveLeagueChat pattern).
    PushMessagingService.instance.setActiveThread(widget.threadId);

    if (_resolvedOtherUserName.trim().isEmpty ||
        _resolvedOtherUserName.trim() == 'User') {
      unawaited(_resolveOtherUserName());
    }
  }

  Future<void> _resolveOtherUserName() async {
    final otherId = _extractOtherUserId();
    if (otherId == null || otherId.isEmpty) return;
    try {
      final name = await _profiles.fetchDisplayNameByUserId(otherId);
      if (!mounted) return;
      if (name.trim().isNotEmpty) {
        setState(() => _resolvedOtherUserName = name.trim());
      }
    } catch (_) {
      // Keep whatever name (possibly the 'User' fallback) is already showing.
    }
  }

  @override
  void dispose() {
    PushMessagingService.instance.setActiveThread(null);
    _recordingTicker?.cancel();
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

  // ── EXTRACT USER ID FALLBACK ─────────────────────────────────────────────
  // If GoRouter fails to pass the ID, we can safely extract it from the
  // deterministic thread ID (dm_uid1_uid2) to ensure the badge always renders.
  String? _extractOtherUserId() {
    if (widget.otherUserId != null && widget.otherUserId!.trim().isNotEmpty) {
      return widget.otherUserId!.trim();
    }
    
    final parts = widget.threadId.split('_');
    if (parts.length == 3 && parts[0] == 'dm') {
      final selfUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (parts[1] == selfUid) return parts[2];
      if (parts[2] == selfUid) return parts[1];
    }
    return null;
  }

  // ── ASSUMPTION: no shared display-name resolver was available in this
  // file (unlike LeagueChatScreen's _senderName()), so this falls back to
  // FirebaseAuth's displayName. Swap this out if the app resolves names
  // via UserProfileRepository elsewhere. ──────────────────────────────────
  String _senderName() {
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    return name.isEmpty ? context.l10n.tr('private_chat_default_sender_name') : name;
  }

  Future<void> _notifyPush({
    required String messageId,
    required String preview,
  }) async {
    final recipientId = _extractOtherUserId();
    if (recipientId == null || recipientId.trim().isEmpty) return;
    if (messageId.trim().isEmpty) return;

    final senderId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (senderId.isEmpty) return;

    await SupabaseEdgeNotificationsService.instance.notifyPrivateMessage(
      threadId: widget.threadId,
      recipientId: recipientId,
      messageId: messageId,
      senderId: senderId,
      senderName: _senderName(),
      preview: preview.trim(),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    await _sendTextLike(raw: text);
  }

  /// Shared by the first send and by retrying a failed one. Shows the
  /// bubble immediately (optimistic UI) instead of waiting on the
  /// Firestore write to complete.
  Future<void> _sendTextLike({
    required String raw,
    String? retryMessageId,
  }) async {
    final selfUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final messageId =
        retryMessageId ?? _repo.newMessageId(widget.threadId);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final optimistic = PrivateMessage(
      id: messageId,
      senderId: selfUid,
      type: PrivateMessageType.text,
      text: raw,
      imageUrl: '',
      voiceUrl: '',
      createdAtMs: nowMs,
      deliveryStatus: ChatDeliveryStatus.sending,
    );

    if (mounted) {
      setState(() => _pendingMessages[messageId] = optimistic);
    }
    _input.clear();

    try {
      await _repo.sendTextMessage(
        threadId: widget.threadId,
        text: raw,
        messageIdOverride: messageId,
      );
      unawaited(_notifyPush(messageId: messageId, preview: raw));
      // _pendingMessages[messageId] is left as "sending" here on purpose --
      // the realtime listener will deliver the confirmed doc under the
      // same id within moments, which supersedes and clears it (see the
      // StreamBuilder below).
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingMessages[messageId] =
            optimistic.copyWith(deliveryStatus: ChatDeliveryStatus.failed);
      });
      _toastErr(e);
    }
  }

  void _retryFailedMessage(PrivateMessage failed) {
    _pendingMessages.remove(failed.id);
    _sendTextLike(raw: failed.text, retryMessageId: failed.id);
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
        _toast(
            (pick.errorMessage ?? context.l10n.tr('private_chat_pick_image_failed')).trim(),
            error: true);
        return;
      }

      final file = pick.file!;
      final url = await _repo.uploadImage(threadId: widget.threadId, file: file);
      final messageId =
          await _repo.sendImageMessage(threadId: widget.threadId, imageUrl: url);
      unawaited(_notifyPush(
          messageId: messageId,
          preview: context.l10n.tr('private_chat_preview_photo')));

      if (mounted) setState(() => _busyWithAttachment = false);
    } catch (e) {
      if (mounted) setState(() => _busyWithAttachment = false);
      _toastErr(e);
    }
  }

  /// Free (no active Pro/Elite plan) users can already read and reply in
  /// an existing private thread, but sending a file attachment is a
  /// paid-only action until they upgrade -- mirrors how
  /// PrivateMessageButton gates STARTING a new thread: redirect to
  /// UpgradePlanScreen instead of letting the picker open and the
  /// Firestore write fail with a raw permission-denied (firestore.rules'
  /// private DM message rule requires an active plan outright for
  /// type == 'image', no free-tier allowance). Checked live rather than
  /// cached, since PlanStatusService is the authoritative, always-fresh
  /// source and this is only a quick single-document read.
  Future<void> _handleImagePick() async {
    if (_busyWithAttachment || _isRecording) return;

    setState(() => _busyWithAttachment = true);
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    bool isPaid = false;
    try {
      isPaid = uid.isEmpty
          ? false
          : await PlanStatusService.instance.isPaidPlanActive(uid);
    } catch (_) {
      isPaid = false;
    }
    if (!mounted) return;
    setState(() => _busyWithAttachment = false);

    if (!isPaid) {
      final upgraded = await UpgradePlanScreen.open(context);
      if (!upgraded || !mounted) return;
    }

    await _pickAndSendImage();
  }

  Future<void> _startRecording() async {
    if (_busyWithAttachment || _isVoiceSending || _isRecording) return;

    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        if (!mounted) return;
        setState(() => _recordingPermissionDenied = true);
        _toast(context.l10n.tr('private_chat_mic_permission_denied'), error: true);
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
      _recordingSegmentStartedAt = DateTime.now();
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() {});
      });

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = outPath;
        _recordingPaused = false;
        _recordedMsBeforePause = 0;
      });
    } catch (e) {
      _toastErr(e);
    }
  }

  /// Pauses the in-progress recording (via the overlay's Pause/Resume
  /// button) -- the underlying recorder is paused for real (record
  /// package's AudioRecorder.pause(), confirmed implemented on both
  /// Android and iOS) -- resuming continues the SAME file/session, nothing
  /// is stitched together client-side.
  Future<void> _pauseRecording() async {
    if (!_isRecording || _recordingPaused) return;
    try {
      await _recorder.pause();
      final segmentStart = _recordingSegmentStartedAt;
      if (!mounted) return;
      setState(() {
        if (segmentStart != null) {
          _recordedMsBeforePause +=
              DateTime.now().difference(segmentStart).inMilliseconds;
        }
        _recordingSegmentStartedAt = null;
        _recordingPaused = true;
      });
    } catch (e) {
      _toastErr(e);
    }
  }

  /// Resumes a paused recording from the Cancel/Resume/Send bar.
  Future<void> _resumeRecording() async {
    if (!_isRecording || !_recordingPaused) return;
    try {
      await _recorder.resume();
      if (!mounted) return;
      setState(() {
        _recordingSegmentStartedAt = DateTime.now();
        _recordingPaused = false;
      });
    } catch (e) {
      _toastErr(e);
    }
  }

  /// Tap the pause/resume icon in the RecordingOverlay -- toggles between
  /// the two methods above.
  Future<void> _togglePauseRecording() =>
      _recordingPaused ? _resumeRecording() : _pauseRecording();

  Future<void> _cancelRecording() async {
    try {
      _recordingTicker?.cancel();
      _recordingTicker = null;
      _recordingSegmentStartedAt = null;

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
        _recordingPaused = false;
        _recordedMsBeforePause = 0;
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
      if (!await file.exists()) {
        throw StateError(context.l10n.tr('private_chat_recording_not_found'));
      }

      // Total captured duration = every completed segment (already
      // accumulated across any pause/resume cycles) plus whatever's been
      // captured in the currently-active segment, if any (not paused).
      final recordedMs = _recordedMsBeforePause +
          (_recordingPaused || _recordingSegmentStartedAt == null
              ? 0
              : DateTime.now().difference(_recordingSegmentStartedAt!).inMilliseconds);

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final voiceUrl = await _repo.uploadVoice(
        threadId: widget.threadId,
        file: PlatformFile(
          name: '$nowMs.m4a',
          path: finalPath,
          size: await file.length(),
        ),
      );

      final messageId = await _repo.sendVoiceMessage(
        threadId: widget.threadId,
        voiceUrl: voiceUrl,
        voiceDurationMs: recordedMs,
      );
      unawaited(_notifyPush(
          messageId: messageId,
          preview: context.l10n.tr('private_chat_preview_voice_message')));

      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingSegmentStartedAt = null;
        _recordedMsBeforePause = 0;
        _isVoiceSending = false;
        _recordingPaused = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVoiceSending = false);
      _toastErr(e);
    }
  }

  Future<void> _handleMessageLongPress(
    BuildContext context,
    PrivateMessage m,
    bool isMe,
    ReactionsRepository reactionsRepo,
  ) async {
    if (isMe) {
      // Can't report your own message -- go straight to the reaction picker,
      // same behavior as before this menu was added.
      final current = await reactionsRepo.watch().first;
      if (!context.mounted) return;
      final picked = await showReactionPicker(context, currentEmoji: current.myEmoji);
      if (picked == null) return;
      await reactionsRepo.toggle(picked);
      return;
    }

    final l10n = context.l10n;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.emoji_emotions_outlined),
              title: Text(l10n.tr('private_chat_react_action')),
              onTap: () => Navigator.of(ctx).pop('react'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l10n.tr('moderation_report_tooltip')),
              onTap: () => Navigator.of(ctx).pop('report'),
            ),
          ],
        ),
      ),
    );

    if (action == 'react') {
      final current = await reactionsRepo.watch().first;
      if (!context.mounted) return;
      final picked = await showReactionPicker(context, currentEmoji: current.myEmoji);
      if (picked == null) return;
      await reactionsRepo.toggle(picked);
    } else if (action == 'report') {
      if (!context.mounted) return;
      showReportSheet(
        context,
        targetUserId: m.senderId,
        targetType: ReportTargetType.message,
        contextId: m.id,
        contextLocation: widget.threadId,
      );
    }
  }

  Widget _buildImageBubble(BuildContext context, PrivateMessage m, bool isMe) {
    return ChatImageMedia(
      imageUrl: m.imageUrl,
      maxWidth: MediaQuery.of(context).size.width * 0.65,
    );
  }

  Widget _buildVoiceBubble(BuildContext context, PrivateMessage m, bool isMe, Brightness brightness) {
    final fg = isMe ? AppTheme.darkText : AppTheme.primaryText(brightness);

    return VoiceMessagePlayer(
      voiceUrl: m.voiceUrl,
      durationMsHint: m.voiceDurationMs,
      width: 220,
      iconColor: fg,
      accentColor: fg,
      trackColor: fg.withOpacity(0.18),
      labelColor: fg.withOpacity(0.75),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final selfUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final resolvedOtherUserId = _extractOtherUserId();

    return GlassScaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: resolvedOtherUserId == null
              ? null
              : () => context.push('/profile/$resolvedOtherUserId'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _resolvedOtherUserName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (resolvedOtherUserId != null) ...[
                const SizedBox(width: 6),
                VerificationBadgeWidget(
                  userId: resolvedOtherUserId,
                  size: 20,
                ),
              ],
            ],
          ),
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
                stream: _messagesStream,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final confirmed = snap.data!; // already newest-first

                  // Drop any optimistic message once the realtime listener
                  // has delivered the confirmed doc under the same id.
                  final confirmedIds = confirmed.map((e) => e.id).toSet();
                  _pendingMessages.removeWhere((id, _) => confirmedIds.contains(id));

                  final pending = _pendingMessages.values.toList()
                    ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
                  final messages = <PrivateMessage>[...pending, ...confirmed];

                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.tr('private_chat_empty_state'),
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

                      final messageRef = _repo.messageRef(widget.threadId, m.id);
                      final reactionsRepo = ReactionsRepository(messageRef);

                      return Align(
                        key: ValueKey(m.id),
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onLongPress: () =>
                                  _handleMessageLongPress(context, m, isMe, reactionsRepo),
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
                            ),
                            if (isMe &&
                                m.deliveryStatus != ChatDeliveryStatus.sent)
                              Padding(
                                padding: const EdgeInsets.only(top: 2, bottom: 2),
                                child: m.deliveryStatus == ChatDeliveryStatus.sending
                                    ? SizedBox(
                                        width: 11,
                                        height: 11,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.6,
                                          color: AppTheme.secondaryText(brightness),
                                        ),
                                      )
                                    : InkWell(
                                        onTap: () => _retryFailedMessage(m),
                                        borderRadius: BorderRadius.circular(999),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.error_outline,
                                              size: 14,
                                              color: Colors.redAccent,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              context.l10n.tr('chat_bubble_retry'),
                                              style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            StreamBuilder<ReactionSummary>(
                              stream: reactionsRepo.watch(),
                              builder: (context, reactSnap) {
                                final summary = reactSnap.data ?? ReactionSummary.empty;
                                if (summary.isEmpty) return const SizedBox.shrink();
                                return ReactionPillBar(
                                  summary: summary,
                                  onTapEmoji: (emoji) => reactionsRepo.toggle(emoji),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_isRecording)
              RecordingOverlay(
                recordedMsBeforePause: _recordedMsBeforePause,
                activeSegmentStartedAt: _recordingSegmentStartedAt,
                paused: _recordingPaused,
                isSending: _isVoiceSending,
                onCancel: _cancelRecording,
                onSend: _sendRecording,
                onPauseResume: _togglePauseRecording,
              ),
            ChatInputBar(
              controller: _input,
              isSending: _busyWithAttachment,
              codeMode: false,
              onToggleCodeMode: () {},
              enabled: !_isRecording,
              onPickImage: _handleImagePick,
              onSend: _send,
              onRecordStart: (!_busyWithAttachment && !_isVoiceSending && !_isRecording)
                  ? _startRecording
                  : () {},
              voiceTooltip: _recordingPermissionDenied
                  ? context.l10n.tr('private_chat_mic_permission_required_tooltip')
                  : context.l10n.tr('private_chat_record_voice_tooltip'),
            ),
          ],
        ),
      ),
    );
  }
}
