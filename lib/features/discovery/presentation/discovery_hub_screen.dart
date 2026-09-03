// lib/features/discovery/presentation/discovery_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

/// The Discovery Hub — Feature 3's landing gateway. Presents clear
/// destinations instead of forcing the user straight into Organizer
/// Discovery. Reuses existing screens/routes wherever they already
/// exist (Organizers → PublicOrganizerDiscoveryScreen via
/// /organizer-discovery, Teams → UserSearchScreen via /search,
/// My Chats → PrivateChatListScreen via /messages).
class DiscoveryHubScreen extends StatelessWidget {
  const DiscoveryHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 100),
          children: [
            Text(
              'DISCOVERY',
              style: TextStyle(
                color: AppTheme.limeAccentDark,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Discover eSportlyic',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Explore competitions, organizers, teams and the global eSportlyic community.',
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _DiscoveryRow(
              icon: Icons.local_fire_department_rounded,
              iconColor: const Color(0xFF22C55E),
              title: 'Public Feed',
              subtitle: "See what's happening in the community",
              badge: 'HOT',
              onTap: () => context.push('/discovery/feed'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.chat_bubble_rounded,
              iconColor: const Color(0xFFBEF264),
              title: 'My Chats',
              subtitle: 'See the users you are chatting with',
              onTap: () => context.push('/messages'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.emoji_events_rounded,
              iconColor: const Color(0xFF38BDF8),
              title: 'Competitions',
              subtitle: 'Find leagues, tournaments and upcoming matches',
              onTap: () => context.push('/discovery/competitions'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.hub_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: 'Organizers',
              subtitle: 'Discover verified organizers and workspaces',
              onTap: () => context.push('/organizer-discovery'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.groups_rounded,
              iconColor: const Color(0xFF2DD4BF),
              title: 'Teams',
              subtitle: 'Find competitive teams and squads',
              onTap: () => context.push('/search'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.public_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'Community',
              subtitle: 'Explore global eSportlyic content and discussions',
              onTap: () => context.push('/discovery/community'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryRow extends StatelessWidget {
  const _DiscoveryRow({
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withOpacity(0.14),
              ),
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
                            color: AppTheme.limeAccent.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppTheme.limeAccentDark.withOpacity(0.4)),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: AppTheme.limeAccentDark,
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
