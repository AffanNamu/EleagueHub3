import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key});

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _textCtrl = TextEditingController();

  bool _sending = false;
  bool _codeMode = false;
  bool _identityResolved = false;
  String _resolvedName = '';
  String _resolvedPhoto = '';

  User get _user => FirebaseAuth.instance.currentUser!;

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  bool get _isSuperAdmin => _user.uid.trim() == _superAdminUid;

  @override
  void initState() {
    super.initState();
    _resolveIdentity();
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

  void _toastErr(Object e) =>
      _toast(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')), error: true);

  // ── FIXED: Separate create vs update to match rules exactly ──
  Future<void> _requestAccess() async {
    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final now = DateTime.now().millisecondsSinceEpoch;
      final docRef = _repo.globalChatRequestDoc(_user.uid);
      final existing = await docRef.get().timeout(const Duration(seconds: 8));

      if (existing.exists) {
        // UPDATE — only status + metadata; hits the update rule cleanly
        await docRef.update(<String, dynamic>{
          'status': 'pending',
          'updatedAtMs': now,
        });
      } else {
        // CREATE — full payload, no merge
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
    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      await _repo.sendGlobalMessage(
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
    if (_sending) return;

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
      );

      _textCtrl.clear();
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toastErr(e);
    }
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('Delete message?'),
        content: const Text('This message will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
      await _repo.deleteGlobalMessage(msg.messageId);
      _toast('Message deleted');
    } catch (e) {
      _toastErr(e);
    }
  }

  Widget _chatBody({required bool canSend}) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _repo.globalChatStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                final err = snap.error;
                final msg =
                    UserFriendlyError.toMessage(err is Object ? err : Exception('unknown'));

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Glass(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 36),
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

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  final isMe = m.senderId.trim() == _user.uid.trim();
                  return ChatBubble(
                    message: m,
                    isMe: isMe,
                    canDelete: _isSuperAdmin,
                    onDelete: _isSuperAdmin ? () => _deleteMessage(m) : null,
                  );
                },
              );
            },
          ),
        ),
        ChatInputBar(
          controller: _textCtrl,
          isSending: _sending,
          codeMode: _codeMode,
          enabled: canSend,
          onToggleCodeMode: () => setState(() => _codeMode = !_codeMode),
          onPickImage: _pickAndSendImage,
          onSend: _sendText,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bypassRequest = _isSuperAdmin;

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient(theme.brightness),
      ),
      child: GlassScaffold(
        appBar: AppBar(
          title: const Text('Global Chat'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (_isSuperAdmin)
              IconButton(
                tooltip: 'Requests',
                onPressed: () => context.push('/admin/global-chat-requests'),
                icon: const Icon(Icons.admin_panel_settings_outlined),
              ),
          ],
        ),
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
                                snap.error is Object ? snap.error! : Exception('unknown')),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.75),
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
                                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: _sending ? null : _requestAccess,
                                        icon: const Icon(Icons.lock_open_rounded),
                                        label: Text(
                                          pending ? 'Pending…' : 'Request access',
                                          style: const TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Only approved users can read and send messages.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withOpacity(0.45),
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
