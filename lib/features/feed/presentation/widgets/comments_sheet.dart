import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/user_friendly_error.dart';
import '../../../../core/locale/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/cloudinary_utils.dart';
import '../../../../core/widgets/glass.dart';
import '../../../moderation/models/user_report.dart';
import '../../../moderation/presentation/report_sheet.dart';
import '../../../profile/data/team_profile_repository.dart';
import '../../data/public_feed_repository.dart';
import '../../models/public_post_comment.dart';

/// NEW (comment bug #4): the comments UI for a Public Feed post. There
/// was previously no comment surface at all -- the comment icon in
/// `_PostCard` had no tap handler and no screen existed to show or add
/// comments. This follows the same modal-sheet shape as
/// `create_post_sheet.dart` for visual consistency with the rest of
/// the feed.
///
/// Threaded replies: comments are flattened one level deep -- a reply
/// always points at a top-level comment's id (never at another reply's
/// id), so the UI only ever needs two visual tiers. Replies render
/// indented under their parent, connected by a vertical line whose
/// height is derived from the reply tile's own layout (via
/// IntrinsicHeight) rather than a fixed guess, so it lines up correctly
/// whether a reply is one line or wraps to several.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String postId,
  required String currentAuthorDisplayName,
  required String currentAuthorPhotoUrl,
}) {
  final repo = PublicFeedRepository();
  final textController = TextEditingController();
  final l10n = context.l10n;
  // Fetched once up front rather than per-build -- fails open to an empty
  // set (nothing hidden) until it resolves, matching this app's existing
  // fail-open convention, since this is a short-lived modal sheet.
  final blockedIdsFuture = TeamProfileRepository().fetchBlockedEitherWayUserIds();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final brightness = Theme.of(ctx).brightness;
      bool sending = false;
      String? error;
      String? replyToCommentId;
      String replyToAuthorName = '';

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          void startReply(PublicPostComment target) {
            setSheetState(() {
              replyToCommentId = target.commentId;
              replyToAuthorName = target.authorDisplayName.isEmpty
                  ? l10n.tr('comments_sheet_author_fallback')
                  : target.authorDisplayName;
            });
          }

          void cancelReply() {
            setSheetState(() {
              replyToCommentId = null;
              replyToAuthorName = '';
            });
          }

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
                parentCommentId: replyToCommentId ?? '',
              );
              textController.clear();
              setSheetState(() {
                sending = false;
                replyToCommentId = null;
                replyToAuthorName = '';
              });
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
                            l10n.tr('comments_sheet_title'),
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
                      child: FutureBuilder<Set<String>>(
                        future: blockedIdsFuture,
                        builder: (context, blockedSnap) {
                          final blockedIds = blockedSnap.data ?? const <String>{};
                          return StreamBuilder<List<PublicPostComment>>(
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
                          final all = snap.data!
                              .where((c) => !blockedIds.contains(c.authorId))
                              .toList(growable: false);
                          if (all.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                l10n.tr('comments_sheet_empty'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.secondaryText(brightness),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }

                          final topLevel = all.where((c) => c.parentCommentId.isEmpty).toList();
                          final repliesByParent = <String, List<PublicPostComment>>{};
                          for (final c in all) {
                            if (c.parentCommentId.isEmpty) continue;
                            repliesByParent.putIfAbsent(c.parentCommentId, () => []).add(c);
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            itemCount: topLevel.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 14),
                            itemBuilder: (context, i) {
                              final c = topLevel[i];
                              final replies = repliesByParent[c.commentId] ?? const <PublicPostComment>[];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _CommentTile(
                                    comment: c,
                                    onReply: () => startReply(c),
                                  ),
                                  if (replies.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Column(
                                        children: [
                                          for (final r in replies)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 10),
                                              child: IntrinsicHeight(
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                                  children: [
                                                    // Thread connector -- stretches to match
                                                    // the reply tile's real height via
                                                    // IntrinsicHeight, so it lines up whether
                                                    // the reply is one line or several.
                                                    SizedBox(
                                                      width: 25,
                                                      child: Center(
                                                        child: Container(
                                                          width: 2,
                                                          color: AppTheme.cardBorder(brightness),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: _CommentTile(
                                                        comment: r,
                                                        isReply: true,
                                                        onReply: () => startReply(c),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          );
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
                    if (replyToCommentId != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.reply_rounded, size: 16, color: AppTheme.limeAccentDark),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${l10n.tr('comments_sheet_replying_to_prefix')} $replyToAuthorName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.secondaryText(brightness),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: cancelReply,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded, size: 16, color: AppTheme.secondaryText(brightness)),
                              ),
                            ),
                          ],
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
                                hintText: replyToCommentId != null
                                    ? l10n.tr('comments_sheet_reply_hint')
                                    : l10n.tr('comments_sheet_hint'),
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
  const _CommentTile({
    required this.comment,
    required this.onReply,
    this.isReply = false,
  });

  final PublicPostComment comment;
  final VoidCallback onReply;
  final bool isReply;

  String _timeAgo(AppLocalizations l10n, int ms) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return l10n.tr('comments_sheet_time_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}${l10n.tr('comments_sheet_time_minutes_suffix')}';
    if (diff.inHours < 24) return '${diff.inHours}${l10n.tr('comments_sheet_time_hours_suffix')}';
    return '${diff.inDays}${l10n.tr('comments_sheet_time_days_suffix')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final avatarRadius = isReply ? 12.0 : 15.0;
    final selfUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final isOwnComment = selfUid.isNotEmpty && selfUid == comment.authorId;

    void openAuthorProfile() {
      try {
        GoRouter.of(context).push('/profile/${comment.authorId}');
      } catch (_) {}
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: openAuthorProfile,
          child: CircleAvatar(
            radius: avatarRadius,
            backgroundColor: AppTheme.iconCircleBackground(brightness),
            backgroundImage: comment.authorPhotoUrl.isNotEmpty
                ? NetworkImage(CloudinaryUtils.thumb(comment.authorPhotoUrl, size: 64))
                : null,
            child: comment.authorPhotoUrl.isEmpty
                ? Icon(Icons.person_rounded, size: avatarRadius)
                : null,
          ),
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
                      child: InkWell(
                        onTap: openAuthorProfile,
                        child: Text(
                          comment.authorDisplayName.isEmpty ? l10n.tr('comments_sheet_author_fallback') : comment.authorDisplayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: isReply ? 11.5 : 12.5,
                            color: AppTheme.primaryText(brightness),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        _timeAgo(l10n, comment.createdAtMs),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontSize: 11,
                        ),
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
                    fontSize: isReply ? 12.5 : 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: onReply,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          l10n.tr('comments_sheet_reply_button'),
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    if (!isOwnComment) ...[
                      const SizedBox(width: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => showReportSheet(
                          context,
                          targetUserId: comment.authorId,
                          targetType: ReportTargetType.comment,
                          contextId: comment.commentId,
                          contextLocation: comment.postId,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            l10n.tr('moderation_report_tooltip'),
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
