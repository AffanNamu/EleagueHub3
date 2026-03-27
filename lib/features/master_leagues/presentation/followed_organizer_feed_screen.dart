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

  IconData _feedIcon(String type) {
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

  Color _feedColor(String type) {
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

  String _formatWhen(int ms) {
    if (ms <= 0) return 'Unknown time';
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms)
          .toLocal()
          .toString()
          .split('.')
          .first;
    } catch (_) {
      return 'Unknown time';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final feed = OrganizerFeedFirebase();

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Followed Organizer Feed'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: uid.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: EmptyState(
                      title: 'Sign in required',
                      message:
                          'Please sign in to view updates from organizers you follow.',
                      icon: Icons.dynamic_feed_rounded,
                    ),
                  )
                : StreamBuilder<List<OrganizerFeedEvent>>(
                    stream: feed.watchFollowedOrganizerFeed(uid),
                    builder: (context, snap) {
                      final items = snap.data ?? const <OrganizerFeedEvent>[];

                      if (snap.connectionState == ConnectionState.waiting &&
                          items.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snap.hasError && items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Glass(
                            borderRadius: 24,
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              'Unable to load organizer updates right now.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.error,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        );
                      }

                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: EmptyState(
                            title: 'No updates yet',
                            message:
                                'Follow organizer workspaces to see their latest activity here.',
                            icon: Icons.dynamic_feed_rounded,
                          ),
                        );
                      }

                      return ListView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
                        children: [
                          Glass(
                            borderRadius: 28,
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Organizer Feed',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Latest updates from the organizer workspaces you follow.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurface.withOpacity(0.72),
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (snap.hasError)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Glass(
                                borderRadius: 18,
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'Some updates may be unavailable right now.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ...items.map((item) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () {
                                  if (item.leagueId.trim().isNotEmpty) {
                                    context.push('/leagues/${item.leagueId.trim()}');
                                    return;
                                  }
                                  if (item.masterLeagueId.trim().isNotEmpty) {
                                    context.push(
                                      '/master-leagues/${item.masterLeagueId.trim()}',
                                    );
                                  }
                                },
                                child: Glass(
                                  borderRadius: 22,
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _feedColor(item.type)
                                              .withOpacity(0.12),
                                          border: Border.all(
                                            color: _feedColor(item.type)
                                                .withOpacity(0.24),
                                          ),
                                        ),
                                        child: Icon(
                                          _feedIcon(item.type),
                                          color: _feedColor(item.type),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: cs.onSurface,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              item.message,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: cs.onSurface
                                                    .withOpacity(0.74),
                                                fontWeight: FontWeight.w700,
                                                height: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                _MetaChip(
                                                  label: item.actorName.trim()
                                                          .isEmpty
                                                      ? 'Organizer'
                                                      : item.actorName.trim(),
                                                  icon: Icons.person_outline_rounded,
                                                  color: cs.primary,
                                                ),
                                                _MetaChip(
                                                  label: _formatWhen(
                                                      item.createdAtMs),
                                                  icon: Icons.schedule_rounded,
                                                  color: cs.primary,
                                                ),
                                                if (item.masterLeagueId
                                                    .trim()
                                                    .isNotEmpty)
                                                  _MetaChip(
                                                    label: item.masterLeagueId
                                                        .trim(),
                                                    icon: Icons.hub_rounded,
                                                    color: const Color(0xFF14B8A6),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: cs.onSurface.withOpacity(0.35),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
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
