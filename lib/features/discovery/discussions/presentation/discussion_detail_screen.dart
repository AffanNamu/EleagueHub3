// lib/features/discovery/discussions/presentation/discussion_detail_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../../auth/data/user_profile_repository.dart';
import '../../../auth/models/user_profile.dart';
import '../data/discussions_repository.dart';
import '../models/discussion_reply.dart';
import '../models/discussion_thread.dart';

class DiscussionDetailScreen extends StatefulWidget {
  const DiscussionDetailScreen({super.key, required this.threadId});
  final String threadId;

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen> {
  final DiscussionsRepository _repo = DiscussionsRepository();
  final UserProfileRepository _userRepo = UserProfileRepository();
  final TextEditingController _replyController = TextEditingController();
  bool _sending = false;

  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final account = await _userRepo.fetchByUserId(_selfUid);
      final name = _userRepo.displayNameForProfile(account, fallbackUserId: _selfUid);
      await _repo.createReply(
        threadId: widget.threadId,
        authorDisplayName: name,
        authorPhotoUrl: account?.effectivePhotoUrl ?? '',
        text: text,
      );
      if (!mounted) return;
      _replyController.clear();
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmDeleteThread() async {
    final brightness = Theme.of(context).brightness;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(brightness),
        title: const Text('Delete this discussion?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.deleteThread(widget.threadId);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  String _timeAgo(int ms) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Discussion'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<DiscussionThread?>(
          stream: _repo.watchThread(widget.threadId),
          builder: (context, threadSnap) {
            final thread = threadSnap.data;
            if (threadSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (thread == null || thread.deleted) {
              return Center(
                child: Text(
                  'This discussion is no longer available.',
                  style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
                ),
              );
            }

            final isOwner = thread.authorId == _selfUid;

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      Glass(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(16),
                        fill: AppTheme.cardColor(brightness),
                        borderColor: AppTheme.cardBorder(brightness),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppTheme.iconCircleBackground(brightness),
                                  backgroundImage: thread.authorPhotoUrl.isNotEmpty
                                      ? NetworkImage(thread.authorPhotoUrl)
                                      : null,
                                  child: thread.authorPhotoUrl.isEmpty
                                      ? const Icon(Icons.person_rounded, size: 16)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    thread.authorDisplayName.isEmpty ? 'User' : thread.authorDisplayName,
                                    style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryText(brightness)),
                                  ),
                                ),
                                Text(
                                  _timeAgo(thread.createdAtMs),
                                  style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12),
                                ),
                                if (isOwner)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.delete_outline_rounded, color: AppTheme.secondaryText(brightness)),
                                    onPressed: _confirmDeleteThread,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              thread.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                            if (thread.body.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                thread.body,
                                style: TextStyle(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${thread.replyCount} ${thread.replyCount == 1 ? "Reply" : "Replies"}',
                        style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primaryText(brightness)),
                      ),
                      const SizedBox(height: 10),
                      StreamBuilder<List<DiscussionReply>>(
                        stream: _repo.watchReplies(widget.threadId),
                        builder: (context, repliesSnap) {
                          final replies = repliesSnap.data ?? const [];
                          if (replies.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No replies yet. Be the first to respond.',
                                style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (final reply in replies) ...[
                                _ReplyTile(reply: reply, timeAgo: _timeAgo(reply.createdAtMs)),
                                const SizedBox(height: 8),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            enabled: !_sending,
                            decoration: const InputDecoration(hintText: 'Write a reply…'),
                            onSubmitted: (_) => _sendReply(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_rounded),
                          color: AppTheme.limeAccentDark,
                          onPressed: _sending ? null : _sendReply,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReplyTile extends StatefulWidget {
  const _ReplyTile({required this.reply, required this.timeAgo});
  final DiscussionReply reply;
  final String timeAgo;

  @override
  State<_ReplyTile> createState() => _ReplyTileState();
}

class _ReplyTileState extends State<_ReplyTile> {
  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  Future<void> _delete(BuildContext context) async {
    try {
      await DiscussionsRepository().deleteReply(threadId: widget.reply.threadId, replyId: widget.reply.replyId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isOwner = widget.reply.authorId == _selfUid;

    return Glass(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppTheme.iconCircleBackground(brightness),
            backgroundImage: widget.reply.authorPhotoUrl.isNotEmpty
                ? NetworkImage(widget.reply.authorPhotoUrl)
                : null,
            child: widget.reply.authorPhotoUrl.isEmpty ? const Icon(Icons.person_rounded, size: 14) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.reply.authorDisplayName.isEmpty ? 'User' : widget.reply.authorDisplayName,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTheme.primaryText(brightness)),
                      ),
                    ),
                    Text(widget.timeAgo, style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 11)),
                    if (isOwner)
                      InkWell(
                        onTap: () => _delete(context),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.close_rounded, size: 16, color: AppTheme.secondaryText(brightness)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.reply.text,
                  style: TextStyle(color: AppTheme.primaryText(brightness), fontWeight: FontWeight.w500, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
