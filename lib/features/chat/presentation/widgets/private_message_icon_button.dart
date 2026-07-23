// lib/features/chat/presentation/widgets/private_message_icon_button.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/private_chat_repository.dart';

/// A compact, icon-only version of PrivateMessageButton meant to sit in
/// a profile header (next to "more"/share) so chat is reachable in one
/// tap without scrolling down to the full-width button.
///
/// Renders nothing when messaging isn't available at all (blocked
/// relationship), matching PrivateMessageButton's behavior.
class PrivateMessageIconButton extends StatefulWidget {
  const PrivateMessageIconButton({
    super.key,
    required this.targetUserId,
    required this.targetDisplayName,
    this.onUpgradeTap,
  });

  final String targetUserId;
  final String targetDisplayName;
  final VoidCallback? onUpgradeTap;

  @override
  State<PrivateMessageIconButton> createState() =>
      _PrivateMessageIconButtonState();
}

class _PrivateMessageIconButtonState extends State<PrivateMessageIconButton> {
  final PrivateChatRepository _repo = PrivateChatRepository();

  late Future<PrivateChatAccessResult> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _repo.checkAccess(widget.targetUserId);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  Future<void> _openExisting(String threadId) async {
    if (!mounted) return;
    context.push('/chat/$threadId', extra: {
      'otherUserId': widget.targetUserId,
      'otherName': widget.targetDisplayName,
    });
  }

  Future<void> _startNew() async {
    try {
      final thread = await _repo.startOrGetThread(widget.targetUserId);
      if (!mounted) return;
      context.push('/chat/${thread.id}', extra: {
        'otherUserId': widget.targetUserId,
        'otherName': widget.targetDisplayName,
      });
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _handleLockedTap() {
    if (widget.onUpgradeTap != null) {
      widget.onUpgradeTap!.call();
      return;
    }
    _snack(
      'Starting a private chat requires Premium. '
      '${widget.targetDisplayName} can still message you first.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PrivateChatAccessResult>(
      future: _accessFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            width: 40,
            height: 40,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final result = snap.data!;
        if (result.access == PrivateChatAccess.blocked) {
          return const SizedBox.shrink();
        }

        final locked = result.access == PrivateChatAccess.locked;

        return Tooltip(
          message: locked ? 'Message (Premium required)' : 'Message',
          child: IconButton(
            onPressed: locked
                ? _handleLockedTap
                : (result.access == PrivateChatAccess.threadExists
                    ? () => _openExisting(result.existingThreadId!)
                    : _startNew),
            style: IconButton.styleFrom(
              backgroundColor: locked
                  ? Colors.black.withOpacity(0.35)
                  : AppTheme.limeAccent,
              foregroundColor: locked ? Colors.white70 : AppTheme.darkText,
              shape: const CircleBorder(),
            ),
            icon: Icon(
              locked ? Icons.lock_outline_rounded : Icons.chat_bubble_rounded,
              size: 20,
            ),
          ),
        );
      },
    );
  }
}
