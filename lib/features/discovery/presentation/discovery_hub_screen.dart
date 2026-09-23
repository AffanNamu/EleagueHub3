// lib/features/discovery/presentation/discovery_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 100),
          children: [
            Text(
              l10n.tr('discovery_hub_eyebrow'),
              style: TextStyle(
                color: AppTheme.limeAccentDark,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.tr('discovery_hub_title'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.primaryText(brightness),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.tr('discovery_hub_subtitle'),
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
              title: l10n.tr('discovery_hub_public_feed_title'),
              subtitle: l10n.tr('discovery_hub_public_feed_subtitle'),
              badge: l10n.tr('discovery_hub_public_feed_badge'),
              onTap: () => context.push('/discovery/feed'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.chat_bubble_rounded,
              iconColor: const Color(0xFFBEF264),
              title: l10n.tr('discovery_hub_my_chats_title'),
              subtitle: l10n.tr('discovery_hub_my_chats_subtitle'),
              onTap: () => context.push('/messages'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.emoji_events_rounded,
              iconColor: const Color(0xFF38BDF8),
              title: l10n.tr('discovery_hub_competitions_title'),
              subtitle: l10n.tr('discovery_hub_competitions_subtitle'),
              onTap: () => context.push('/discovery/competitions'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.hub_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: l10n.tr('discovery_hub_organizers_title'),
              subtitle: l10n.tr('discovery_hub_organizers_subtitle'),
              onTap: () => context.push('/organizer-discovery'),
            ),
            const SizedBox(height: 10),
            // Not run through l10n.tr(): this repo's translation set is
            // pre-generated across every supported language (see
            // app_localizations_*.dart), and adding one new key here would
            // only exist in English until a full translation pass — same
            // documented, accepted interim state as the ~650 other
            // hardcoded strings already in this codebase pending l10n.
            _DiscoveryRow(
              icon: Icons.dynamic_feed_rounded,
              iconColor: const Color(0xFFEC4899),
              title: 'Organizer Feed',
              subtitle: 'Updates from organizers you follow',
              onTap: () => context.push('/organizer-feed'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.groups_rounded,
              iconColor: const Color(0xFF2DD4BF),
              title: l10n.tr('discovery_hub_teams_title'),
              subtitle: l10n.tr('discovery_hub_teams_subtitle'),
              onTap: () => context.push('/search'),
            ),
            const SizedBox(height: 10),
            _DiscoveryRow(
              icon: Icons.public_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: l10n.tr('discovery_hub_community_title'),
              subtitle: l10n.tr('discovery_hub_community_subtitle'),
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
