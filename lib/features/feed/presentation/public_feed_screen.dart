// lib/features/feed/presentation/public_feed_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/reactions/message_reaction.dart';
import '../../../core/reactions/presentation/reaction_picker.dart';
import '../../../core/reactions/presentation/reaction_pill_bar.dart';
import '../../../core/reactions/reactions_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/cloudinary_utils.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../highlights/presentation/highlight_player_screen.dart';
import '../../moderation/models/user_report.dart';
import '../../moderation/presentation/report_sheet.dart';
import '../../profile/data/team_profile_repository.dart';
import '../../verification/presentation/widgets/verification_badge_widget.dart';
import '../data/public_feed_repository.dart';
import '../models/public_post.dart';
import 'widgets/comments_sheet.dart';
import 'widgets/create_post_sheet.dart';

/// Cloudinary can generate a still frame for any uploaded video by
/// swapping `/video/upload/` for `/video/upload/so_0/` and the extension
/// for `.jpg` -- no separate thumbnail upload/storage needed.
String _cloudinaryVideoThumbnail(String videoUrl) {
  final marker = '/video/upload/';
  final idx = videoUrl.indexOf(marker);
  if (idx == -1) return '';
  final withTransform =
      videoUrl.replaceFirst(marker, '${marker}so_0,w_900,c_limit/');
  final dotIdx = withTransform.lastIndexOf('.');
  if (dotIdx <= idx) return '$withTransform.jpg';
  return '${withTransform.substring(0, dotIdx)}.jpg';
}

enum _FeedTab { forYou, latest }

/// Bundles what the feed screen needs about the signed-in user: just
/// their profile, for display name/photo when composing a post.
///
/// FIXED: this used to also gate the create-post FAB on an active
/// Pro/Elite entitlement (`eligible`), a leftover from when posting was
/// Pro/Elite-only. Free-tier posting (2/day, enforced server-side by
/// firestore.rules + PublicFeedRepository.createPost's rate limiter)
/// was added later, but this screen's FAB was never updated to match --
/// it kept hiding the create-post button entirely for any signed-in
/// user without a paid plan, even though they were now fully able to
/// post. Any signed-in user can see the button now; the daily cap is
/// still enforced, just server-side rather than by hiding the UI.
class _FeedBootstrap {
  const _FeedBootstrap({required this.account});
  final UserProfile? account;
}

class PublicFeedScreen extends StatefulWidget {
  const PublicFeedScreen({super.key});

  @override
  State<PublicFeedScreen> createState() => _PublicFeedScreenState();
}

class _PublicFeedScreenState extends State<PublicFeedScreen> {
  final PublicFeedRepository _repo = PublicFeedRepository();
  final UserProfileRepository _userRepo = UserProfileRepository();

  _FeedTab _tab = _FeedTab.forYou;

  // FIXED (like UI bug #3): tracks whether the current user has liked
  // each visible post. Previously the heart icon was hardcoded to
  // `favorite_border` with no state backing it at all, so it could
  // never reflect a like. Populated lazily per post via
  // PublicFeedRepository.hasLiked(), and flipped optimistically (with
  // rollback on failure) when the user taps the heart.
  final Map<String, bool> _likedCache = {};

  Set<String> _blockedUserIds = <String>{};

  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  @override
  void initState() {
    super.initState();
    TeamProfileRepository().fetchBlockedEitherWayUserIds().then((ids) {
      if (!mounted) return;
      setState(() => _blockedUserIds = ids);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  Future<_FeedBootstrap> _loadBootstrap() async {
    final account = await _userRepo.fetchByUserId(_selfUid);
    return _FeedBootstrap(account: account);
  }

  Future<void> _handleCreateTap(UserProfile? account) async {
    final displayName = _userRepo.displayNameForProfile(account, fallbackUserId: _selfUid);
    final result = await showCreatePostSheet(
      context,
      authorDisplayName: displayName,
      authorPhotoUrl: account?.effectivePhotoUrl ?? '',
    );
    if (result == true && mounted) {
      _snack(context.l10n.tr('public_feed_post_created'));
    }
  }

  void _ensureLikeStatusLoaded(String postId) {
    if (_likedCache.containsKey(postId)) return;
    // Placeholder so we don't kick off a fetch for this post on every
    // build while the real answer is in flight.
    _likedCache[postId] = false;
    _repo.hasLiked(postId).then((liked) {
      if (!mounted) return;
      if (liked && _likedCache[postId] != true) {
        setState(() => _likedCache[postId] = true);
      }
    });
  }

  Future<void> _handleLike(String postId) async {
    final previous = _likedCache[postId] ?? false;
    setState(() => _likedCache[postId] = !previous);
    try {
      await _repo.toggleLike(postId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _likedCache[postId] = previous);
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  // FIXED (comment bug #4): previously nothing was wired to the comment
  // icon at all -- no repository method, no rules, no screen. This opens
  // the new comments bottom sheet, using the current user's profile info
  // (already loaded for the compose sheet) as the comment's author.
  void _handleComment(String postId, UserProfile? account) {
    final displayName = _userRepo.displayNameForProfile(account, fallbackUserId: _selfUid);
    showCommentsSheet(
      context,
      postId: postId,
      currentAuthorDisplayName: displayName,
      currentAuthorPhotoUrl: account?.effectivePhotoUrl ?? '',
    );
  }

  Future<void> _confirmDelete(String postId) async {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(brightness),
        title: Text(l10n.tr('public_feed_delete_dialog_title')),
        content: Text(l10n.tr('public_feed_delete_dialog_message')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.tr('public_feed_delete_dialog_cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.tr('public_feed_delete_dialog_confirm'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.deletePost(postId);
      if (mounted) _snack(l10n.tr('public_feed_post_deleted'));
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('public_feed_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<_FeedBootstrap>(
          future: _selfUid.isEmpty
              ? Future.value(const _FeedBootstrap(account: null))
              : _loadBootstrap(),
          builder: (context, bootstrapSnap) {
            final bootstrap = bootstrapSnap.data;
            final account = bootstrap?.account;

            return Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TabChip(
                              label: l10n.tr('public_feed_tab_for_you'),
                              selected: _tab == _FeedTab.forYou,
                              onTap: () => setState(() => _tab = _FeedTab.forYou),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TabChip(
                              label: l10n.tr('public_feed_tab_latest'),
                              selected: _tab == _FeedTab.latest,
                              onTap: () => setState(() => _tab = _FeedTab.latest),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<List<PublicPost>>(
                        stream: _tab == _FeedTab.forYou
                            ? _repo.watchForYouFeed()
                            : _repo.watchLatestFeed(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Text(
                                UserFriendlyError.toMessage(snap.error as Object),
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            );
                          }
                          if (!snap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final posts = snap.data!
                              .where((p) => !_blockedUserIds.contains(p.authorId))
                              .toList(growable: false);
                          if (posts.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  l10n.tr('public_feed_empty'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                            itemCount: posts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final post = posts[i];
                              _ensureLikeStatusLoaded(post.postId);
                              final isLiked = _likedCache[post.postId] ?? false;
                              return _PostCard(
                                post: post,
                                isOwner: post.authorId == _selfUid,
                                isLiked: isLiked,
                                onLike: () => _handleLike(post.postId),
                                onComment: () => _handleComment(post.postId, account),
                                onDelete: () => _confirmDelete(post.postId),
                                onOpenLeague: post.leagueId.trim().isEmpty
                                    ? null
                                    : () => context.push('/leagues/${post.leagueId.trim()}'),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                if (_selfUid.isNotEmpty)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                      onPressed: () => _handleCreateTap(account),
                      child: const Icon(Icons.add_rounded),
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

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? AppTheme.limeAccent : AppTheme.tabInactiveBackground(brightness),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.darkText : AppTheme.tabInactiveText(brightness),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

/// A stateful widget to handle the manual toggle of audio on images
class _AudioToggleButton extends StatefulWidget {
  final String audioUrl;
  const _AudioToggleButton({required this.audioUrl});

  @override
  State<_AudioToggleButton> createState() => _AudioToggleButtonState();
}

class _AudioToggleButtonState extends State<_AudioToggleButton> {
  bool _isPlaying = false;

  void _toggleAudio() {
    setState(() {
      _isPlaying = !_isPlaying;
    });

    // TODO: Add your Audio Player package logic here!
    // Example using 'audioplayers' package:
    // if (_isPlaying) {
    //   audioPlayer.play(UrlSource(widget.audioUrl));
    // } else {
    //   audioPlayer.pause();
    // }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleAudio,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isPlaying ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.isOwner,
    required this.isLiked,
    required this.onLike,
    required this.onComment,
    required this.onDelete,
    required this.onOpenLeague,
  });

  final PublicPost post;
  final bool isOwner;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onDelete;
  final VoidCallback? onOpenLeague;

  void _showPostActions(BuildContext context) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(l10n.tr('public_feed_delete_post')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDelete();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(l10n.tr('moderation_report_tooltip')),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showReportSheet(
                    context,
                    targetUserId: post.authorId,
                    targetType: ReportTargetType.post,
                    contextId: post.postId,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  DocumentReference<Map<String, dynamic>> get _postRef =>
      FirebaseFirestore.instance.collection('public_posts').doc(post.postId);

  String _timeAgo(AppLocalizations l10n, int ms) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return l10n.tr('public_feed_time_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}${l10n.tr('public_feed_time_minutes_suffix')}';
    if (diff.inHours < 24) return '${diff.inHours}${l10n.tr('public_feed_time_hours_suffix')}';
    return '${diff.inDays}${l10n.tr('public_feed_time_days_suffix')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  try {
                    GoRouter.of(context).push('/profile/${post.authorId}');
                  } catch (_) {}
                },
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.iconCircleBackground(brightness),
                  backgroundImage: post.authorPhotoUrl.isNotEmpty
                      ? NetworkImage(CloudinaryUtils.thumb(post.authorPhotoUrl, size: 72))
                      : null,
                  child: post.authorPhotoUrl.isEmpty ? const Icon(Icons.person_rounded, size: 18) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () {
                    try {
                      GoRouter.of(context).push('/profile/${post.authorId}');
                    } catch (_) {}
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          post.authorDisplayName.isEmpty ? l10n.tr('public_feed_author_fallback') : post.authorDisplayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryText(brightness),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // NEW: shows the author's verified badge (Green for
                      // Pro, Green + Organizer/gold for Elite) right after
                      // their name, Twitter/Facebook-style. Reuses the
                      // existing VerificationBadgeWidget + badgeStreamProvider
                      // -- badges are already granted on plan purchase by
                      // MasterLeaguePaymentService/GooglePlayBillingService,
                      // so this is live, not computed from the post itself.
                      VerificationBadgeWidget(userId: post.authorId, size: 15),
                    ],
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  _timeAgo(l10n, post.createdAtMs),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_vert_rounded, color: AppTheme.secondaryText(brightness)),
                onPressed: () => _showPostActions(context),
              ),
            ],
          ),
          if (post.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.text,
              style: TextStyle(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],

          // NEW: Social Media Sizing & Audio Overlay
          if (post.mediaUrl.trim().isNotEmpty && post.mediaType == 'video') ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => openHighlightPlayer(
                context,
                videoUrl: post.mediaUrl,
                title: post.authorDisplayName,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 450, minHeight: 200),
                  child: SizedBox(
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: brightness == Brightness.dark
                              ? AppTheme.darkCard
                              : const Color(0xFFE5E7EB),
                          child: Image.network(
                            _cloudinaryVideoThumbnail(post.mediaUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        Container(color: Colors.black.withOpacity(0.18)),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ] else if (post.mediaUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 450, // Social media max height
                      minHeight: 200,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Image.network(
                        CloudinaryUtils.fit(post.mediaUrl, width: 1080),
                        fit: BoxFit.cover, // Ensures normal social media crop
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  // If the image has an audio file attached, show the manual play button
                  if (post.audioUrl.trim().isNotEmpty)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: _AudioToggleButton(audioUrl: post.audioUrl),
                    ),
                ],
              ),
            ),
          ],

          if (post.leagueId.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: onOpenLeague,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.searchBackground(brightness),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.searchOutline(brightness)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: AppTheme.limeAccentDark, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        post.leagueName.isEmpty ? l10n.tr('public_feed_view_competition') : post.leagueName,
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(brightness)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: onLike,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      // FIXED (like UI bug #3): the heart previously always
                      // rendered `favorite_border` regardless of like state,
                      // because no per-post "did I like this" state existed
                      // anywhere above it. It now reflects `isLiked`, which
                      // is hydrated from PublicFeedRepository.hasLiked() and
                      // flipped optimistically on tap.
                      Icon(
                        isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 18,
                        color: isLiked ? const Color(0xFFE0245E) : AppTheme.secondaryText(brightness),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${post.likeCount}',
                        style: TextStyle(
                          color: isLiked ? const Color(0xFFE0245E) : AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              // FIXED (comment bug #4): this row previously had no
              // InkWell/GestureDetector at all -- tapping it did nothing
              // because nothing was listening for the tap. Now opens the
              // comments sheet, using the same lime-accent color used
              // elsewhere in the feed for interactive/active states.
              InkWell(
                onTap: onComment,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: AppTheme.limeAccentDark,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${post.commentCount}',
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              // Emoji reactions -- additive to the heart-like above, not a
              // replacement. Self-contained: builds its own doc ref/repo
              // rather than threading one down through every caller.
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () async {
                  final repo = ReactionsRepository(_postRef);
                  final current = await repo.watch().first;
                  if (!context.mounted) return;
                  final picked = await showReactionPicker(
                    context,
                    currentEmoji: current.myEmoji,
                  );
                  if (picked == null) return;
                  await repo.toggle(picked);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Icon(
                    Icons.add_reaction_outlined,
                    size: 18,
                    color: AppTheme.secondaryText(brightness),
                  ),
                ),
              ),
            ],
          ),
          StreamBuilder<ReactionSummary>(
            stream: ReactionsRepository(_postRef).watch(),
            builder: (context, snap) {
              final summary = snap.data ?? ReactionSummary.empty;
              if (summary.isEmpty) return const SizedBox.shrink();
              return ReactionPillBar(
                summary: summary,
                onTapEmoji: (emoji) => ReactionsRepository(_postRef).toggle(emoji),
              );
            },
          ),
        ],
      ),
    );
  }
}
