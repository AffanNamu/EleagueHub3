import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';

// ---------------------------------------------------------------------------
// MasterLeagueEntryTile
// ---------------------------------------------------------------------------
// Pure presentational widget. No navigation logic.
// Receives all callbacks from parent — clean separation.
// No responsive layout needed — Row with Expanded works at any width.
// ---------------------------------------------------------------------------

class MasterLeagueEntryTile extends StatelessWidget {
  const MasterLeagueEntryTile({
    super.key,
    required this.isSignedIn,
    required this.unlocked,
    required this.loading,
    required this.priceText,
    required this.onOpen,
    required this.onUnlock,
    required this.onSignIn,
  });

  final bool         isSignedIn;
  final bool         unlocked;
  final bool         loading;
  final String       priceText;
  final VoidCallback onOpen;
  final VoidCallback onUnlock;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final brightness = theme.brightness;

    // ── Derived display values ─────────────────────────────────────────────

    final String subtitle;
    if (!isSignedIn) {
      subtitle = 'Sign in to create and manage '
          'Master Leagues.';
    } else if (loading) {
      subtitle = 'Checking your access...';
    } else if (unlocked) {
      subtitle = 'Open your Master Leagues, view '
          'created and joined leagues.';
    } else {
      subtitle = priceText.isEmpty
          ? 'Open Master Leagues and proceed to '
              'payment during creation.'
          : 'Open Master Leagues • current plan '
              'price: $priceText';
    }

    final Color badgeColor;
    if (!isSignedIn) {
      badgeColor = AppTheme.secondaryText(brightness);
    } else if (unlocked) {
      badgeColor = const Color(0xFF22C55E);
    } else {
      badgeColor = const Color(0xFFF59E0B);
    }

    final String badgeLabel;
    if (!isSignedIn) {
      badgeLabel = 'SIGN IN';
    } else if (unlocked) {
      badgeLabel = 'READY';
    } else {
      badgeLabel = 'PAY AS YOU CREATE';
    }

    final String actionLabel =
        !isSignedIn ? 'Sign in' : 'Open';

    final VoidCallback action =
        !isSignedIn ? onSignIn : onOpen;

    // ── Layout ─────────────────────────────────────────────────────────────

    return Glass(
      borderRadius: 22,
      padding:      EdgeInsets.zero,
      fill:         AppTheme.cardColor(brightness),
      borderColor:  AppTheme.cardBorder(brightness),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient:
              AppTheme.leagueCardGradient(brightness),
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width:  46,
              height: 46,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                color:  AppTheme.iconCircleBackground(
                    brightness),
                border: Border.all(
                    color:
                        AppTheme.cardBorder(brightness)),
              ),
              child: Icon(
                Icons.hub_rounded,
                color: AppTheme.limeAccentDark,
                size:  22,
              ),
            ),
            const SizedBox(width: 12),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // Title + badge row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Master League',
                          maxLines:  1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: theme
                              .textTheme.titleSmall
                              ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryText(
                                brightness),
                          ),
                        ),
                      ),
                      // Badge
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical:   6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(999),
                          color: badgeColor.withOpacity(
                            brightness ==
                                    Brightness.dark
                                ? 0.14
                                : 0.10,
                          ),
                          border: Border.all(
                            color: badgeColor.withOpacity(
                              brightness ==
                                      Brightness.dark
                                  ? 0.28
                                  : 0.22,
                            ),
                          ),
                        ),
                        child: Text(
                          badgeLabel,
                          style: theme
                              .textTheme.labelSmall
                              ?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Subtitle
                  Text(
                    subtitle,
                    maxLines:  2,
                    overflow:  TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(
                      color: AppTheme.secondaryText(
                          brightness),
                      fontWeight: FontWeight.w700,
                      height:     1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Action button
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                ),
              ),
              onPressed: loading ? null : action,
              child: loading
                  ? const SizedBox(
                      width:  18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkText,
                      ),
                    )
                  : Text(
                      actionLabel,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
