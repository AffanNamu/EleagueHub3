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
import '../../master_leagues/domain/master_league_plan.dart';
import '../data/public_feed_repository.dart';
import '../models/public_post.dart';
import 'widgets/create_post_sheet.dart';

enum _FeedTab { forYou, latest }

class PublicFeedScreen extends StatefulWidget {
  const PublicFeedScreen({super.key});

  @override
  State<PublicFeedScreen> createState() => _PublicFeedScreenState();
}

class _PublicFeedScreenState extends State<PublicFeedScreen> {
  final PublicFeedRepository _repo = PublicFeedRepository();
  final UserProfileRepository _userRepo = UserProfileRepository();

  _FeedTab _tab = _FeedTab.forYou;

  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
    );
  }

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

  Future<void> _handleLike(String postId) async {
    try {
      await _repo.toggleLike(postId);
    } catch (e) {
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
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
        child: FutureBuilder<UserProfile?>(
          future: _selfUid.isEmpty ? Future.value(null) : _userRepo.fetchByUserId(_selfUid),
          builder: (context, accountSnap) {
            final account = accountSnap.data;
            final eligible = account != null &&
                (account.activePlan == MasterLeaguePlan.pro ||
                    account.activePlan == MasterLeaguePlan.elite);

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
                              return _PostCard(
                                post: post,
                                isOwner: post.authorId == _selfUid,
                                onLike: () => _handleLike(post.postId),
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

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.isOwner,
    required this.onLike,
    required this.onDelete,
    required this.onOpenLeague,
  });

  final PublicPost post;
  final bool isOwner;
  final VoidCallback onLike;
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
                child: Text(
                  post.authorDisplayName.isEmpty ? 'User' : post.authorDisplayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                  overflow: TextOverflow.ellipsis,
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
          if (post.mediaUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                post.mediaUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                      Icon(Icons.favorite_border_rounded, size: 18, color: AppTheme.secondaryText(brightness)),
                      const SizedBox(width: 6),
                      Text(
                        '${post.likeCount}',
                        style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppTheme.secondaryText(brightness)),
              const SizedBox(width: 6),
              Text(
                '${post.commentCount}',
                style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
