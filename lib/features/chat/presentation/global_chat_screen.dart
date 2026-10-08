import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/push_messaging_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/services/supabase_edge_notifications_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../moderation/models/user_report.dart';
import '../../moderation/presentation/report_sheet.dart';
import '../../profile/data/team_profile_repository.dart';
import '../data/chat_repository.dart';
import '../models/chat_message.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/pinned_message_bar.dart';

class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key});

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  Map<String, ChatMessage> _msgById = <String, ChatMessage>{};

  /// Optimistic messages keyed by the client-generated id used as their
  /// Firestore doc id, shown immediately on send before the write (and the
  /// realtime listener's own echo of it) confirms. Dropped once the
  /// listener delivers a doc with the same id (see the StreamBuilder
  /// below) or replaced with a [ChatDeliveryStatus.failed] copy on error.
  final Map<String, ChatMessage> _pendingMessages = <String, ChatMessage>{};

  final ValueNotifier<String?> _selectedMessageId = ValueNotifier<String?>(null);
  final ValueNotifier<ChatMessage?> _replyTo = ValueNotifier<ChatMessage?>(null);

  bool _sending = false;
  bool _codeMode = false;
  bool _identityResolved = false;
  String _resolvedName = '';
  String _resolvedPhoto = '';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _adminsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _globalModerationSub;
  bool _allowSenderPinGlobal = false;

  bool _globalChatMuted = false;
  bool _globalChatBanned = false;
  bool _globalModerationResolved = false;

  Set<String> _blockedUserIds = <String>{};

  User get _user => FirebaseAuth.instance.currentUser!;

  bool get _isSelecting => (_selectedMessageId.value ?? '').trim().isNotEmpty;

  DocumentReference<Map<String, dynamic>> get _globalModerationDoc =>
      FirebaseFirestore.instance
          .collection('app')
          .doc('chatModeration')
          .collection('users')
          .doc(_user.uid.trim());

  bool get _chatBlocked => _globalChatBanned;
  bool get _chatReadOnly => _globalChatMuted;

  @override
  void initState() {
    super.initState();
    _resolveIdentity();
    _listenAdminsDoc();
    _watchGlobalModeration();
    _loadBlockedUserIds();

    PushMessagingService.instance.subscribeToGlobalChatTopic();
    PushMessagingService.instance.setActiveLeagueChat('global');
  }

  Future<void> _loadBlockedUserIds() async {
    final ids = await TeamProfileRepository().fetchBlockedEitherWayUserIds();
    if (!mounted) return;
    setState(() => _blockedUserIds = ids);
  }

  void _watchGlobalModeration() {
    _globalModerationSub = _globalModerationDoc
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _globalChatMuted = data['allChatMuted'] == true;
        _globalChatBanned = data['allChatBanned'] == true;
        _globalModerationResolved = true;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _globalChatMuted = false;
        _globalChatBanned = false;
        _globalModerationResolved = true;
      });
    });
  }

  void _listenAdminsDoc() {
    _adminsSub = _repo.appAdminsDocStream().listen((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      final allowSenderPin = data['allowGlobalSenderPin'];
      final allow = allowSenderPin is bool ? allowSenderPin : false;

      if (!mounted) return;
      setState(() {
        _allowSenderPinGlobal = allow;
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
    return context.l10n.tr('global_chat_default_player_name');
  }

  String _fallbackPhoto() => (_user.photoURL ?? '').trim();

  String _senderName() {
    if (_identityResolved && _resolvedName.isNotEmpty) return _resolvedName;
    return _fallbackName();
  }

  String _senderPhoto() {
    if (_identityResolved) return _resolvedPhoto;
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

  Future<void> _requestAccess() async {
    setState(() => _sending = true);
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final now = DateTime.now().millisecondsSinceEpoch;
      final docRef = _repo.globalChatRequestDoc(_user.uid);
      final existing = await docRef.get().timeout(const Duration(seconds: 8));

      if (existing.exists) {
        await docRef.update(<String, dynamic>{
          'status': 'pending',
          'updatedAtMs': now,
        });
      } else {
        await docRef.set(<String, dynamic>{
          'userId': _user.uid,
          'userName': _senderName(),
          'userPhoto': _senderPhoto(),
          'status': 'pending',
          'createdAtMs': now,
          'updatedAtMs': now,
        });
      }

      _toast(context.l10n.tr('global_chat_request_submitted'));
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  String _newMessageId() => FirebaseFirestore.instance.collection('_ids').doc().id;

  String _previewForOutgoing({
    required String type,
    required String text,
    required String imageUrl,
  }) {
    final t = type.trim();
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
    await SupabaseEdgeNotificationsService.instance.notifyGlobalChatMessage(
      messageId: messageId,
      senderId: _user.uid.trim(),
      senderName: _senderName().trim(),
      preview: preview.trim(),
    );
  }

  Future<void> _sendText() async {
    if (_chatBlocked) {
      _toast(context.l10n.tr('global_chat_banned_message'), error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast(context.l10n.tr('global_chat_muted_message'), error: true);
      return;
    }
    if (_isSelecting) return;

    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) return;

    final reply = _replyTo.value;
    final type = _codeMode ? ChatMessageType.code : ChatMessageType.text;
    await _sendTextLike(
      raw: raw,
      type: type,
      replyToMessageId: reply?.messageId ?? '',
      replyToSenderName: reply?.displaySenderName ?? '',
      replyToText: reply?.replyPreview() ?? '',
      replyToType: reply?.type ?? '',
    );
  }

  /// Shared by the first send and by retrying a failed one. Builds a local
  /// "sending" bubble and shows it immediately (optimistic UI) -- the
  /// caller doesn't wait on the network round trip to see their message.
  Future<void> _sendTextLike({
    required String raw,
    required String type,
    required String replyToMessageId,
    required String replyToSenderName,
    required String replyToText,
    required String replyToType,
    String? retryMessageId,
  }) async {
    final messageId = retryMessageId ?? _newMessageId();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final optimistic = ChatMessage(
      messageId: messageId,
      senderId: _user.uid.trim(),
      senderName: _senderName(),
      senderPhoto: _senderPhoto(),
      text: raw,
      imageUrl: '',
      voiceUrl: '',
      type: type,
      createdAt: null,
      createdAtMs: nowMs,
      leagueId: '',
      timestamp: nowMs,
      pinned: false,
      pinnedAt: null,
      pinnedBy: '',
      deleted: false,
      deletedAt: null,
      deletedBy: '',
      replyToMessageId: replyToMessageId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
      replyToType: replyToType,
      deliveryStatus: ChatDeliveryStatus.sending,
    );

    if (mounted) {
      setState(() => _pendingMessages[messageId] = optimistic);
    }
    _textCtrl.clear();
    _replyTo.value = null;

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      await _repo.sendGlobalMessage(
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: type,
        text: raw,
        messageIdOverride: messageId,
        replyToMessageId: optimistic.replyToMessageId,
        replyToSenderName: optimistic.replyToSenderName,
        replyToText: optimistic.replyToText,
        replyToType: optimistic.replyToType,
      );

      final preview = _previewForOutgoing(
        type: type,
        text: raw,
        imageUrl: '',
      );
      _notifyPush(messageId: messageId, preview: preview);
      // _pendingMessages[messageId] is left as "sending" here on purpose --
      // the realtime listener will deliver the confirmed doc under the
      // same id within moments, which supersedes and clears it (see the
      // StreamBuilder below). No need to flip a local "sent" state first.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingMessages[messageId] =
            optimistic.copyWith(deliveryStatus: ChatDeliveryStatus.failed);
      });
      _toastErr(e);
    }
  }

  void _retryFailedMessage(ChatMessage failed) {
    _pendingMessages.remove(failed.messageId);
    _sendTextLike(
      raw: failed.text,
      type: failed.type,
      replyToMessageId: failed.replyToMessageId,
      replyToSenderName: failed.replyToSenderName,
      replyToText: failed.replyToText,
      replyToType: failed.replyToType,
      retryMessageId: failed.messageId,
    );
  }

  Future<void> _pickAndSendImage() async {
    if (_chatBlocked) {
      _toast(context.l10n.tr('global_chat_banned_message'), error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast(context.l10n.tr('global_chat_muted_message'), error: true);
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
        final msg =
            (pick.errorMessage ?? context.l10n.tr('global_chat_pick_image_failed')).trim();
        _toast(msg, error: true);
        return;
      }

      final url = await _repo.uploadGlobalChatImage(file: pick.file!);

      await _repo.sendGlobalMessage(
        senderId: _user.uid,
        senderName: _senderName(),
        senderPhoto: _senderPhoto(),
        type: ChatMessageType.image,
        text: _textCtrl.text.trim(),
        imageUrl: url,
        messageIdOverride: messageId,
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.displaySenderName ?? '',
        replyToText: reply?.replyPreview() ?? '',
        replyToType: reply?.type ?? '',
      );

      final preview = _previewForOutgoing(
        type: ChatMessageType.image,
        text: _textCtrl.text.trim(),
        imageUrl: url,
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

  bool _canDeleteMessage(ChatMessage msg) {
    return _user.uid.trim() == msg.senderId.trim();
  }

  bool _canPinMessage(ChatMessage msg) {
    final isSender = _user.uid.trim() == msg.senderId.trim();
    return _allowSenderPinGlobal && isSender;
  }

  Future<void> _softDeleteSelected(ChatMessage msg) async {
    if (!_canDeleteMessage(msg)) {
      _toast(context.l10n.tr('global_chat_delete_own_only'), error: true);
      return;
    }
    if (msg.deleted) {
      _toast(context.l10n.tr('global_chat_already_deleted'));
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      await _repo.softDeleteGlobalMessage(
        messageId: msg.messageId,
        deletedBy: _user.uid,
      );
      _selectedMessageId.value = null;
      _toast(context.l10n.tr('global_chat_message_deleted'));
    } catch (e) {
      _toastErr(e);
    }
  }

  Future<void> _pinSelected(ChatMessage msg) async {
    if (!_canPinMessage(msg)) {
      _toast(context.l10n.tr('global_chat_pin_permission_denied'), error: true);
      return;
    }
    if (msg.deleted) {
      _toast(context.l10n.tr('global_chat_cannot_pin_deleted'), error: true);
      _selectedMessageId.value = null;
      return;
    }

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      await _repo.pinGlobalMessage(
        messageId: msg.messageId,
        pinnedBy: _user.uid,
        unpinPrevious: false,
      );
      _selectedMessageId.value = null;
      _toast(context.l10n.tr('global_chat_pinned'));
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
      contextLocation: 'global',
    );
  }

  Future<void> _copySelected(ChatMessage msg) async {
    if (msg.deleted) {
      _toast(context.l10n.tr('global_chat_nothing_to_copy'), error: true);
      _selectedMessageId.value = null;
      return;
    }

    final txt = msg.text.trim().isNotEmpty
        ? msg.text.trim()
        : (msg.type == ChatMessageType.image
            ? msg.imageUrl.trim()
            : (msg.type == ChatMessageType.voice
                ? msg.voiceUrl.trim()
                : ''));

    if (txt.isEmpty) {
      _toast(context.l10n.tr('global_chat_nothing_to_copy'), error: true);
      _selectedMessageId.value = null;
      return;
    }

    await Clipboard.setData(ClipboardData(text: txt));
    _toast(context.l10n.tr('global_chat_copied'));
    _selectedMessageId.value = null;
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) {
      _toast(context.l10n.tr('global_chat_message_not_loaded'));
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final brightness = Theme.of(context).brightness;

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ValueListenableBuilder<String?>(
        valueListenable: _selectedMessageId,
        builder: (context, selectedId, _) {
          final selecting = (selectedId ?? '').trim().isNotEmpty;

          if (!selecting) {
            return AppBar(
              title: Text(context.l10n.tr('global_chat_title')),
            );
          }

          final selectedMsg =
              (selectedId != null) ? _msgById[selectedId] : null;

          return AppBar(
            leading: IconButton(
              tooltip: context.l10n.tr('global_chat_cancel_selection_tooltip'),
              onPressed: () => _selectedMessageId.value = null,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text(context.l10n.tr('global_chat_one_selected')),
            actions: [
              IconButton(
                tooltip: context.l10n.tr('common_copy'),
                onPressed:
                    selectedMsg == null ? null : () => _copySelected(selectedMsg),
                icon: const Icon(Icons.copy_rounded),
              ),
              if (selectedMsg != null && _canDeleteMessage(selectedMsg))
                IconButton(
                  tooltip: context.l10n.tr('global_chat_delete_tooltip'),
                  onPressed: () => _softDeleteSelected(selectedMsg),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              if (selectedMsg != null && _canPinMessage(selectedMsg))
                IconButton(
                  tooltip: context.l10n.tr('global_chat_pin_tooltip'),
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

  Widget _moderationBanner(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    if (_globalModerationResolved && _chatBlocked) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(14),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Row(
            children: [
              Icon(
                Icons.block_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.tr('global_chat_banned_full_message'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_globalModerationResolved && _chatReadOnly) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(14),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Row(
            children: [
              const Icon(
                Icons.volume_off_rounded,
                color: Color(0xFFF59E0B),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.tr('global_chat_muted_full_message'),
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
      );
    }

    return const SizedBox.shrink();
  }

  Widget _chatBody({required bool canSend}) {
    return Column(
      children: [
        _moderationBanner(context),
        StreamBuilder<ChatMessage?>(
          stream: _repo.globalPinnedMessageStream(),
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
            stream: _repo.globalChatStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                final err = snap.error;
                final msg = UserFriendlyError.toMessage(
                  err is Object ? err : Exception('unknown'),
                );

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Glass(
                      padding: const EdgeInsets.all(16),
                      fill: AppTheme.cardColor(
                        Theme.of(context).brightness,
                      ),
                      borderColor: AppTheme.cardBorder(
                        Theme.of(context).brightness,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                            size: 36,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            msg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.secondaryText(
                                Theme.of(context).brightness,
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.limeAccent,
                              foregroundColor: AppTheme.darkText,
                            ),
                            onPressed: () => setState(() {}),
                            child: Text(context.l10n.tr('common_retry')),
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

              // Drop any optimistic message once the realtime listener
              // has delivered the confirmed doc under the same id.
              final confirmedIds = msgs.map((e) => e.messageId).toSet();
              _pendingMessages.removeWhere((id, _) => confirmedIds.contains(id));

              final pending = _pendingMessages.values.toList()
                ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
              final combined = <ChatMessage>[...pending, ...msgs];

              if (combined.isEmpty) {
                return Center(
                  child: Text(
                    context.l10n.tr('global_chat_no_messages'),
                    style: TextStyle(
                      color: AppTheme.secondaryText(
                        Theme.of(context).brightness,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }

              _msgById = {for (final m in combined) m.messageId: m};

              final ids = combined.map((e) => e.messageId).toSet();
              _messageKeys.removeWhere((k, _) => !ids.contains(k));

              return ListView.builder(
                controller: _scrollCtrl,
                reverse: true,
                padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                itemCount: combined.length,
                itemBuilder: (_, i) {
                  final m = combined[i];
                  final isMe = m.senderId.trim() == _user.uid.trim();

                  final key = _messageKeys.putIfAbsent(
                    m.messageId,
                    () => GlobalKey(),
                  );

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
                          messageRef: _repo.globalMessageRef(m.messageId),
                          onRetryFailed: m.deliveryStatus == ChatDeliveryStatus.failed
                              ? () => _retryFailedMessage(m)
                              : null,
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
                          onSwipeReply: selecting
                              ? null
                              : () {
                                  _replyTo.value = m;
                                },
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
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
                enabled:
                    canSend && !selecting && !_chatReadOnly && !_chatBlocked,
                onToggleCodeMode: () => setState(() => _codeMode = !_codeMode),
                onPickImage: () {
                  if (_chatReadOnly || _chatBlocked) return;
                  _pickAndSendImage();
                },
                onSend: () {
                  if (_chatReadOnly || _chatBlocked) return;
                  _sendText();
                },
                replySenderName: reply?.displaySenderName,
                replyPreview: reply?.replyPreview(),
                onCancelReply: () => _replyTo.value = null,
              );
            },
          ),
      ],
    );
  }

  @override
  void dispose() {
    PushMessagingService.instance.setActiveLeagueChat(null);
    _adminsSub?.cancel();
    _globalModerationSub?.cancel();
    _scrollCtrl.dispose();
    _selectedMessageId.dispose();
    _replyTo.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return WillPopScope(
      onWillPop: () async {
        if (_isSelecting) {
          _selectedMessageId.value = null;
          return false;
        }
        return true;
      },
      child: GlassScaffold(
        appBar: _buildAppBar(),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _repo.globalChatRequestDoc(_user.uid).snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Glass(
                          padding: const EdgeInsets.all(16),
                          fill: AppTheme.cardColor(brightness),
                          borderColor: AppTheme.cardBorder(brightness),
                          child: Text(
                            UserFriendlyError.toMessage(
                              snap.error is Object
                                  ? snap.error!
                                  : Exception('unknown'),
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final data = snap.data?.data();
                  final statusRaw = (data?['status'] as String? ?? '').trim();
                  final status = statusRaw.toLowerCase();

                  final approved = status == 'approved';
                  final pending = status == 'pending';
                  final rejected = status == 'rejected';

                  if (!approved) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Glass(
                            padding: const EdgeInsets.all(18),
                            fill: AppTheme.cardColor(brightness),
                            borderColor: AppTheme.cardBorder(brightness),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.tr('global_chat_access_required_title'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color:
                                            AppTheme.primaryText(brightness),
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  pending
                                      ? context.l10n.tr('global_chat_pending_message')
                                      : rejected
                                          ? context.l10n.tr('global_chat_rejected_message')
                                          : context.l10n.tr('global_chat_request_prompt'),
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppTheme.limeAccent,
                                          foregroundColor: AppTheme.darkText,
                                        ),
                                        onPressed:
                                            _sending ? null : _requestAccess,
                                        icon:
                                            const Icon(Icons.lock_open_rounded),
                                        label: Text(
                                          pending
                                              ? context.l10n.tr('global_chat_pending_button')
                                              : context.l10n.tr('global_chat_request_access_button'),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  context.l10n.tr('global_chat_approved_only_note'),
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return _chatBody(canSend: true);
                },
              ),
      ),
    );
  }
}
