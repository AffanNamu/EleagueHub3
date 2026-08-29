// lib/features/feed/presentation/public_feed_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../master_leagues/logic/master_league_entitlement_service.dart';
import '../../verification/presentation/widgets/verification_badge_widget.dart';
import '../data/public_feed_repository.dart';
import '../models/public_post.dart';
import 'widgets/comments_sheet.dart';
import 'widgets/create_post_sheet.dart';

enum _FeedTab { forYou, latest }

/// Bundles what the feed screen needs about the signed-in user:
/// their profile (for display name/photo when composing a post) and
/// whether they're currently eligible to post.
///
/// FIXED (entitlement bug #1): `eligible` is now resolved via
/// [MasterLeagueEntitlementService.getEntitlement], which checks the
/// Firestore profile AND falls back to Auth custom claims
/// (organizerPro/organizerProPlan) if the profile hasn't synced yet.
/// Previously this screen read `UserProfile.activePlan` directly off
/// the Firestore profile with no claims fallback -- the same gap that
/// `MasterLeagueEntitlementService.activateAfterPayment()`'s own
/// comments warn about ("best-effort local profile mirror ... if it
/// fails, ... still works via the custom claim"). A Google Play user
/// whose profile mirror write failed after a successful, verified
/// purchase was claims-active everywhere else but got told here that
/// they couldn't create a post.
class _FeedBootstrap {
  const _FeedBootstrap({required this.account, required this.eligible});
  final UserProfile? account;
  final bool eligible;
}

class PublicFeedScreen extends StatefulWidget {
  const PublicFeedScreen({super.key});

  @override
  State<PublicFeedScreen> createState() => _PublicFeedScreenState();
}

class _PublicFeedScreenState extends State<PublicFeedScreen> {
  final PublicFeedRepository _repo = PublicFeedRepository();
  final UserProfileRepository _userRepo = UserProfileRepository();
  final MasterLeagueEntitlementService _entitlementService =
      MasterLeagueEntitlementService();

  _FeedTab _tab = _FeedTab.forYou;

  // FIXED (like UI bug #3): tracks whether the current user has liked
  // each visible post. Previously the heart icon was hardcoded to
  // `favorite_border` with no state backing it at all, so it could
  // never reflect a like. Populated lazily per post via
  // PublicFeedRepository.hasLiked(), and flipped optimistically (with
  // rollback on failure) when the user taps the heart.
  final Map<String, bool> _likedCache = {};

  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

  Future<_FeedBootstrap> _loadBootstrap() async {
    final results = await Future.wait<Object?>([
      _userRepo.fetchByUserId(_selfUid),
      _entitlementService.getEntitlement(),
    ]);

    final account = results[0] as UserProfile?;
    final entitlement = results[1] as OrganizerProEntitlement;

    final eligible = entitlement.active &&
        entitlement.plan != null &&
        !entitlement.plan!.isFree;

    return _FeedBootstrap(account: account, eligible: eligible);
  }

  // NOTE: You will need to update `showCreatePostSheet` inside `create_post_sheet.dart` 
  // to collect an `audioUrl` and pass it to the repository's `createPost` method!
  Future<void> _handleCreateTap(UserProfile? account) async {
    final displayName = _userRepo.displayNameForProfile(account, fallbackUserId: _selfUid);
    final result = await showCreatePostSheet(
      context,
      authorDisplayName: displayName,
      authorPhotoUrl: account?.effectivePhotoUrl ?? '',
    );
    if (result == true && mounted) {
      _snack('Posted to the community feed.');
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
    final brightness = Theme.of(context).brightness;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(brightness),
        title: const Text('Delete this post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.deletePost(postId);
      if (mounted) _snack('Post deleted.');
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Public Feed'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<_FeedBootstrap>(
          future: _selfUid.isEmpty
              ? Future.value(const _FeedBootstrap(account: null, eligible: false))
              : _loadBootstrap(),
          builder: (context, bootstrapSnap) {
            final bootstrap = bootstrapSnap.data;
            final account = bootstrap?.account;
            final eligible = bootstrap?.eligible ?? false;

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
                              label: 'For You',
                              selected: _tab == _FeedTab.forYou,
                              onTap: () => setState(() => _tab = _FeedTab.forYou),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TabChip(
                              label: 'Latest',
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
                          final posts = snap.data!;
                          if (posts.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No posts yet. Be the first to share something with the community.',
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
                if (eligible)
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
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.iconCircleBackground(brightness),
                backgroundImage:
                    post.authorPhotoUrl.isNotEmpty ? NetworkImage(post.authorPhotoUrl) : null,
                child: post.authorPhotoUrl.isEmpty ? const Icon(Icons.person_rounded, size: 18) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        post.authorDisplayName.isEmpty ? 'User' : post.authorDisplayName,
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
              Text(
                _timeAgo(post.createdAtMs),
                style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12),
              ),
              if (isOwner)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.more_vert_rounded, color: AppTheme.secondaryText(brightness)),
                  onPressed: onDelete,
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
          if (post.mediaUrl.trim().isNotEmpty) ...[
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
                        post.mediaUrl,
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
                        post.leagueName.isEmpty ? 'View competition' : post.leagueName,
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
            ],
          ),
        ],
      ),
    );
  }
}
