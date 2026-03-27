import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/organizer_feed_firebase.dart';
import '../domain/organizer_feed_event.dart';

class FollowedOrganizerFeedScreen extends StatelessWidget {
  const FollowedOrganizerFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final feed = OrganizerFeedFirebase();

    if (uid.isEmpty) {
      return GlassScaffold(
        appBar: AppBar(
          title: const Text('Followed Organizer Feed'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(
          child: EmptyState(
            title: 'Sign in required',
            message: 'Please sign in to view your followed organizer feed.',
            icon: Icons.login_rounded,
          ),
        ),
      );
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Followed Organizer Feed'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<List<OrganizerFeedEvent>>(
          stream: feed.watchFollowedOrganizerFeed(uid),
          builder: (context, snap) {
            final items = snap.data ?? const <OrganizerFeedEvent>[];

            if (snap.hasError) {
              return Center(
                child: Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${snap.error}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            }

            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (items.isEmpty) {
              return const Center(
                child: EmptyState(
                  title: 'No followed organizer activity yet',
                  message:
                      'Follow organizer workspaces to see announcements, new competitions, and verification updates here.',
                  icon: Icons.dynamic_feed_rounded,
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return _FeedItemCard(item: item);
              },
            );
          },
        ),
      ),
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  const _FeedItemCard({required this.item});

  final OrganizerFeedEvent item;

  Color _typeColor(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement':
        return const Color(0xFF8B5CF6);
      case 'competition_created':
        return const Color(0xFF22C55E);
      case 'verification_approved':
        return const Color(0xFF1D9BF0);
      case 'verification_renewed':
        return const Color(0xFF14B8A6);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _typeIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement':
        return Icons.campaign_outlined;
      case 'competition_created':
        return Icons.emoji_events_outlined;
      case 'verification_approved':
        return Icons.verified_rounded;
      case 'verification_renewed':
        return Icons.refresh_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type.trim().toLowerCase()) {
      case 'announcement':
        return 'Announcement';
      case 'competition_created':
        return 'Competition';
      case 'verification_approved':
        return 'Verified';
      case 'verification_renewed':
        return 'Renewed';
      default:
        return 'Update';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _typeColor(item.type);

    return InkWell(
      onTap: () {
        if (item.leagueId.trim().isNotEmpty) {
          context.push('/leagues/${item.leagueId.trim()}');
          return;
        }
        if (item.masterLeagueId.trim().isNotEmpty) {
          context.push('/master-leagues/${item.masterLeagueId.trim()}');
        }
      },
      borderRadius: BorderRadius.circular(22),
      child: Glass(
        borderRadius: 22,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.12),
                border: Border.all(color: color.withOpacity(0.28)),
              ),
              child: Icon(_typeIcon(item.type), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: color.withOpacity(0.12),
                          border: Border.all(color: color.withOpacity(0.28)),
                        ),
                        child: Text(
                          _typeLabel(item.type),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.78),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metaChip(
                        context,
                        icon: Icons.person_outline_rounded,
                        label: item.actorName.trim().isEmpty
                            ? 'Organizer'
                            : item.actorName.trim(),
                      ),
                      _metaChip(
                        context,
                        icon: Icons.schedule_rounded,
                        label: item.createdAtMs > 0
                            ? DateTime.fromMillisecondsSinceEpoch(
                                    item.createdAtMs)
                                .toLocal()
                                .toString()
                                .split('.')
                                .first
                            : 'Unknown time',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurface.withOpacity(0.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.primary.withOpacity(0.06),
        border: Border.all(color: cs.primary.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
