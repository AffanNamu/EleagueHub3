//chat/presentation/private message button
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/private_chat_repository.dart';

/// Drop-in "Message" action for a public profile. Resolves whether the
/// viewer can start a chat, can reply to an existing one, or is locked
/// out (free user, no prior thread) — and renders the right state
/// instead of letting the user tap into a permission error.
class PrivateMessageButton extends StatefulWidget {
  const PrivateMessageButton({
    super.key,
    required this.targetUserId,
    required this.targetDisplayName,
    this.onUpgradeTap,
  });

  final String targetUserId;
  final String targetDisplayName;

  /// Called when a locked (free) user taps the disabled-looking button.
  /// Typically navigates to the upgrade/pricing screen. If null, a
  /// snackbar explanation is shown instead.
  final VoidCallback? onUpgradeTap;

  @override
  State<PrivateMessageButton> createState() => _PrivateMessageButtonState();
}

class _PrivateMessageButtonState extends State<PrivateMessageButton> {
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
    final brightness = Theme.of(context).brightness;

    return FutureBuilder<PrivateChatAccessResult>(
      future: _accessFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 40,
            width: 40,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final result = snap.data!;
        switch (result.access) {
          case PrivateChatAccess.threadExists:
            return FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed: () => _openExisting(result.existingThreadId!),
              icon: const Icon(Icons.message_rounded),
              label: const Text('Message'),
            );
          case PrivateChatAccess.canStart:
            return FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed: _startNew,
              icon: const Icon(Icons.message_rounded),
              label: const Text('Message'),
            );
          case PrivateChatAccess.locked:
            return OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secondaryText(brightness),
                side: BorderSide(color: AppTheme.cardBorder(brightness)),
              ),
              onPressed: _handleLockedTap,
              icon: const Icon(Icons.lock_outline_rounded, size: 18),
              label: const Text('Message (Premium)'),
            );
          case PrivateChatAccess.blocked:
            // No button at all — a blocked relationship shouldn't even
            // hint that messaging exists as an option.
            return const SizedBox.shrink();
        }
      },
    );
  }
}
