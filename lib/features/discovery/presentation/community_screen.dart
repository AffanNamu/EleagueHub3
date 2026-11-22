// lib/features/discovery/presentation/community_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
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
/// Highlights now pushes to CommunityHighlightsScreen, a community-wide
/// HighlightsFeedRepositoryFirebase.watchAllHighlights() feed. Guides is
/// not listed until it exists (no "coming soon" placeholder rows).
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('community_appbar_title')),
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
                    l10n.tr('community_header_title'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: AppTheme.primaryText(brightness),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.tr('community_header_subtitle'),
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
              title: l10n.tr('community_global_chat_title'),
              subtitle: l10n.tr('community_global_chat_subtitle'),
              onTap: () => context.push('/global-chat'),
            ),
            const SizedBox(height: 10),
            _CommunityRow(
              icon: Icons.chat_bubble_outline_rounded,
              iconColor: const Color(0xFF22C55E),
              title: l10n.tr('community_discussions_title'),
              subtitle: l10n.tr('community_discussions_subtitle'),
              onTap: () => context.push('/discovery/community/discussions'),
            ),
            const SizedBox(height: 10),
            _CommunityRow(
              icon: Icons.local_movies_outlined,
              iconColor: const Color(0xFF38BDF8),
              title: l10n.tr('community_highlights_title'),
              subtitle: l10n.tr('community_highlights_subtitle'),
              onTap: () => context.push('/discovery/community/highlights'),
            ),
            // No "Guides" row until Guides exists: a "Soon" entry that only
            // shows "coming soon" is placeholder content (App Review 2.1).
          ],
        ),
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
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AppTheme.primaryText(brightness),
                    ),
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
