import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  bool _sending = false;
  bool _codeMode = false;
  bool _identityResolved = false;
  String _resolvedName = '';
  String _resolvedPhoto = '';

  User get _user => FirebaseAuth.instance.currentUser!;

  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  bool get _isSuperAdmin => _user.uid.trim() == _superAdminUid;
  bool get _isOrganizer =>
      widget.organizerUid != null &&
      widget.organizerUid!.trim().isNotEmpty &&
      widget.organizerUid!.trim() == _user.uid.trim();
  bool get _canModerate => _isSuperAdmin || _isOrganizer;

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

  Future<void> _sendText() async {
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
      await _repo.deleteLeagueMessage(
        leagueId: widget.leagueId,
        messageId: msg.messageId,
      );
      _toast('Message deleted');
    } catch (e) {
      _toastErr(e);
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient(theme.brightness),
      ),
      child: GlassScaffold(
        appBar: AppBar(
          title: const Text('League Chat'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _repo.leagueChatStream(widget.leagueId),
                builder: (context, snap) {
                  if (snap.hasError) {
                    final msg = UserFriendlyError.toMessage(
                        snap.error is Object ? snap.error! : Exception('unknown'));

                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Glass(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline,
                                  color: theme.colorScheme.primary, size: 34),
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
                            fontWeight: FontWeight.w700),
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
                        canDelete: _canModerate,
                        onDelete: _canModerate ? () => _deleteMessage(m) : null,
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
              enabled: true,
              onToggleCodeMode: () => setState(() => _codeMode = !_codeMode),
              onPickImage: _pickAndSendImage,
              onSend: _sendText,
            ),
          ],
        ),
      ),
    );
  }
}
