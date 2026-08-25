// lib/features/discovery/presentation/community_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

/// Community pillar of the Discovery Hub.
///
/// Global Chat has been RELOCATED here from the Home Shell's Explore
/// list per request — it is still the exact same GlobalChatScreen and
/// approval-request flow at the exact same '/global-chat' route,
/// completely untouched. Only the entry point moved, so there is
/// deliberately no second chat system here.
///
/// Discussions is genuinely new (see discussions/ subfolder).
///
/// Highlights and Guides are intentionally left as "coming soon" for
/// now: Highlights should reuse the existing
/// HighlightsFeedRepositoryFirebase with a community-wide query
/// instead of a per-league one, but that requires the actual source of
/// that repository (not yet available) to wire correctly rather than
/// guessing its API surface. Guides is the least-defined of the four
/// pillars and is deferred by design until its content model is
/// decided, per the earlier plan.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Community'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Glass(
              borderRadius: 24,
              padding: const EdgeInsets.all(18),
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'eSportlyic Community',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chat live, start discussions, and explore the wider eSportlyic community.',
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CommunityRow(
              icon: Icons.forum_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Global Chat',
              subtitle: 'Request access & chat with the community in realtime',
              onTap: () => context.push('/global-chat'),
            ),
            const SizedBox(height: 10),
            _CommunityRow(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: const Color(0xFF22C55E),
              title: 'Discussions',
              subtitle: 'Ask questions, share tips, and talk tactics',
              onTap: () => context.push('/discovery/community/discussions'),
            ),
            const SizedBox(height: 10),
            _CommunityRow(
              icon: Icons.local_movies_outlined,
              iconColor: const Color(0xFF38BDF8),
              title: 'Highlights',
              subtitle: 'Community match highlights',
              badge: 'Soon',
              onTap: () => _showComingSoon(context, 'Highlights'),
            ),
            const SizedBox(height: 10),
            _CommunityRow(
              icon: Icons.menu_book_outlined,
              iconColor: const Color(0xFFF59E0B),
              title: 'Guides',
              subtitle: 'Tips, strategy, and how-tos from the community',
              badge: 'Soon',
              onTap: () => _showComingSoon(context, 'Guides'),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$feature is coming soon.'),
      ),
    );
  }
}

class _CommunityRow extends StatelessWidget {
  const _CommunityRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Glass(
        borderRadius: 20,
        padding: const EdgeInsets.all(14),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconColor.withOpacity(0.14)),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryText(brightness).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.cardBorder(brightness)),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText(brightness)),
          ],
        ),
      ),
    );
  }
}
