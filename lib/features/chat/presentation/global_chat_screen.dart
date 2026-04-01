import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
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

  final ValueNotifier<String?> _selectedMessageId = ValueNotifier<String?>(null);
  final ValueNotifier<ChatMessage?> _replyTo = ValueNotifier<ChatMessage?>(null);

  bool _sending = false;
  bool _codeMode = false;
  bool _identityResolved = false;
  String _resolvedName = '';
  String _resolvedPhoto = '';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _adminsSub;
  Set<String> _globalChatAdmins = <String>{};
  bool _allowSenderPinGlobal = false;

  bool _globalChatMuted = false;
  bool _globalChatBanned = false;
  bool _globalModerationResolved = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  bool get _isSuperAdmin => _user.uid.trim() == _superAdminUid;

  bool get _isSelecting => (_selectedMessageId.value ?? '').trim().isNotEmpty;
  bool get _isGlobalAdmin => _globalChatAdmins.contains(_user.uid.trim());

  DocumentReference<Map<String, dynamic>> get _globalModerationDoc =>
      FirebaseFirestore.instance
          .collection('app')
          .doc('chatModeration')
          .collection('users')
          .doc(_user.uid.trim());

  bool get _chatBlocked => _globalChatBanned && !_isSuperAdmin;
  bool get _chatReadOnly => _globalChatMuted && !_isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _resolveIdentity();
    _listenAdminsDoc();
    _watchGlobalModeration();
  }

  void _watchGlobalModeration() {
    _globalModerationDoc.snapshots(includeMetadataChanges: true).listen((snap) {
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
      final rawAdmins = data['globalChatAdmins'];
      final allowSenderPin = data['allowGlobalSenderPin'];

      final admins = <String>{};
      if (rawAdmins is List) {
        for (final v in rawAdmins) {
          if (v is String && v.trim().isNotEmpty) admins.add(v.trim());
        }
      }

      final allow = allowSenderPin is bool ? allowSenderPin : false;

      if (!mounted) return;
      setState(() {
        _globalChatAdmins = admins;
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
    return 'Player';
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

      _toast('Request submitted');
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  Future<void> _sendText() async {
    if (_chatBlocked) {
      _toast('You are banned from Global Chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in Global Chat.', error: true);
      return;
    }
    if (_isSelecting) return;

    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) return;

    final reply = _replyTo.value;

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      await _repo.sendGlobalMessage(
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
      _toast('You are banned from Global Chat.', error: true);
      return;
    }
    if (_chatReadOnly) {
      _toast('You are muted in Global Chat.', error: true);
      return;
    }
    if (_sending || _isSelecting) return;

    final reply = _replyTo.value;

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
        final msg = (pick.errorMessage ?? 'Could not pick image.').trim();
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

  bool _canDeleteMessage(ChatMessage msg) {
    if (_isSuperAdmin) return true;
    if (_isGlobalAdmin) return true;
    return _user.uid.trim() == msg.senderId.trim();
  }

  bool _canPinMessage(ChatMessage msg) {
    if (_isSuperAdmin) return true;
    if (_isGlobalAdmin) return true;
    final isSender = _user.uid.trim() == msg.senderId.trim();
    return _allowSenderPinGlobal && isSender;
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
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      await _repo.softDeleteGlobalMessage(
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

    final isAdmin = _isSuperAdmin || _isGlobalAdmin;

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      await _repo.pinGlobalMessage(
        messageId: msg.messageId,
        pinnedBy: _user.uid,
        unpinPrevious: isAdmin,
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
            : (msg.type == ChatMessageType.voice
                ? msg.voiceUrl.trim()
                : ''));

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

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ValueListenableBuilder<String?>(
        valueListenable: _selectedMessageId,
        builder: (context, selectedId, _) {
          final selecting = (selectedId ?? '').trim().isNotEmpty;

          if (!selecting) {
            return AppBar(
              title: const Text('Global Chat'),
              actions: [
                if (_isSuperAdmin)
                  IconButton(
                    tooltip: 'Requests',
                    onPressed: () =>
                        context.push('/admin/global-chat-requests'),
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                    ),
                  ),
              ],
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
            actions: [
              IconButton(
                tooltip: 'Copy',
                onPressed:
                    selectedMsg == null ? null : () => _copySelected(selectedMsg),
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

  Widget _moderationBanner(BuildContext context) {
    final theme = Theme.of(context);

    if (_globalModerationResolved && _chatBlocked) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.block_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You are banned from Global Chat. You can no longer send messages here.',
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
      );
    }

    if (_globalModerationResolved && _chatReadOnly) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.volume_off_rounded, color: Color(0xFFF59E0B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You are muted in Global Chat. You can read messages but cannot send new ones.',
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
    final theme = Theme.of(context);

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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                            size: 36,
                          ),
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
                            onPressed: () => setState(() {}),
                            child: const Text('Retry'),
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

              _msgById = {for (final m in msgs) m.messageId: m};

              final ids = msgs.map((e) => e.messageId).toSet();
              _messageKeys.removeWhere((k, _) => !ids.contains(k));

              return ListView.builder(
                controller: _scrollCtrl,
                reverse: true,
                padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  final isMe = m.senderId.trim() == _user.uid.trim();

                  final key = _messageKeys.putIfAbsent(
                    m.messageId,
                    () => GlobalKey(),
                  );

                  return ValueListenableBuilder<String?>(
                    valueListenable: _selectedMessageId,
                    builder: (context, selectedId, _) {
                      final selecting = (selectedId ?? '').trim().isNotEmpty;

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
              final selecting = (_selectedMessageId.value ?? '').trim().isNotEmpty;
              final reply = _replyTo.value;

              return ChatInputBar(
                controller: _textCtrl,
                isSending: _sending,
                codeMode: _codeMode,
                enabled: canSend && !selecting && !_chatReadOnly && !_chatBlocked,
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
    _adminsSub?.cancel();
    _scrollCtrl.dispose();
    _selectedMessageId.dispose();
    _replyTo.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bypassRequest = _isSuperAdmin;

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
        body: bypassRequest
            ? _chatBody(canSend: true)
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _repo.globalChatRequestDoc(_user.uid).snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Glass(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            UserFriendlyError.toMessage(
                              snap.error is Object
                                  ? snap.error!
                                  : Exception('unknown'),
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.75),
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Access required',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  pending
                                      ? 'Your request is pending admin approval.'
                                      : rejected
                                          ? 'Your request was rejected. You can request again.'
                                          : 'Request access to join the global public chatroom.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.65),
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed:
                                            _sending ? null : _requestAccess,
                                        icon: const Icon(Icons.lock_open_rounded),
                                        label: Text(
                                          pending ? 'Pending…' : 'Request access',
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
                                  'Only approved users can read and send messages.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.45),
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
