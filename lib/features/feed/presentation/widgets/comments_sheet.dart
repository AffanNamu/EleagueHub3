import 'package:flutter/material.dart';

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../data/public_feed_repository.dart';
import '../../models/public_post_comment.dart';

/// NEW (comment bug #4): the comments UI for a Public Feed post. There
/// was previously no comment surface at all -- the comment icon in
/// `_PostCard` had no tap handler and no screen existed to show or add
/// comments. This follows the same modal-sheet shape as
/// `create_post_sheet.dart` for visual consistency with the rest of
/// the feed.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String postId,
  required String currentAuthorDisplayName,
  required String currentAuthorPhotoUrl,
}) {
  final repo = PublicFeedRepository();
  final textController = TextEditingController();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final brightness = Theme.of(ctx).brightness;
      bool sending = false;
      String? error;

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final text = textController.text.trim();
            if (text.isEmpty) return;

            setSheetState(() {
              sending = true;
              error = null;
            });

            try {
              await repo.addComment(
                postId: postId,
                authorDisplayName: currentAuthorDisplayName,
                authorPhotoUrl: currentAuthorPhotoUrl,
                text: text,
              );
              textController.clear();
              setSheetState(() => sending = false);
            } catch (e) {
              setSheetState(() {
                sending = false;
                error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(brightness),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.cardBorder(brightness)),
                ),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Row(
                        children: [
                          Text(
                            'Comments',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: AppTheme.primaryText(brightness),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: StreamBuilder<List<PublicPostComment>>(
                        stream: repo.watchComments(postId),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                UserFriendlyError.toMessage(snap.error as Object),
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            );
                          }
                          if (!snap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final comments = snap.data!;
                          if (comments.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No comments yet. Be the first to say something.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.secondaryText(brightness),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            itemCount: comments.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final c = comments[i];
                              return _CommentTile(comment: c);
                            },
                          );
                        },
                      ),
                    ),
                    if ((error ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Text(
                          error!.trim(),
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: textController,
                              maxLength: 500,
                              minLines: 1,
                              maxLines: 4,
                              enabled: !sending,
                              style: TextStyle(
                                color: AppTheme.primaryText(brightness),
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: 'Add a comment…',
                                hintStyle: TextStyle(color: AppTheme.secondaryText(brightness)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: AppTheme.cardBorder(brightness)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: AppTheme.cardBorder(brightness)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Colorful send button, matching the lime-accent
                          // treatment used for the heart/like icon and the
                          // "Post to Feed" button elsewhere in the feed.
                          Material(
                            color: AppTheme.limeAccent,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: sending ? null : submit,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: sending
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: AppTheme.darkText,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send_rounded,
                                        color: AppTheme.darkText,
                                        size: 20,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() => textController.dispose());
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final PublicPostComment comment;

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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: AppTheme.iconCircleBackground(brightness),
          backgroundImage: comment.authorPhotoUrl.isNotEmpty
              ? NetworkImage(comment.authorPhotoUrl)
              : null,
          child: comment.authorPhotoUrl.isEmpty
              ? const Icon(Icons.person_rounded, size: 15)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Glass(
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            fill: AppTheme.searchBackground(brightness),
            borderColor: AppTheme.searchOutline(brightness),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.authorDisplayName.isEmpty ? 'User' : comment.authorDisplayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          color: AppTheme.primaryText(brightness),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _timeAgo(comment.createdAtMs),
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.text,
                  style: TextStyle(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
