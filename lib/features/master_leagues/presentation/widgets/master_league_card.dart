import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/cloudinary_utils.dart';
import '../../../../core/widgets/glass.dart';
import '../../domain/master_league.dart';
import '../../domain/master_league_plan.dart';

// ---------------------------------------------------------------------------
// Breakpoints — card-level
// ---------------------------------------------------------------------------

class _BP {
  /// When the card's OWN available width exceeds this value,
  /// switch to the desktop render style (flat container, no blur).
  /// This is intentionally lower than the shell breakpoint (1180)
  /// because the card sits inside a content area that is already
  /// narrower than the screen.
  static const double desktop = 680;
}

// ---------------------------------------------------------------------------
// MasterLeagueCard
// ---------------------------------------------------------------------------

class MasterLeagueCard extends StatelessWidget {
  const MasterLeagueCard({
    super.key,
    required this.masterLeague,
    this.onTap,
  });

  final MasterLeague  masterLeague;
  final VoidCallback? onTap;

  // ── Plan color ────────────────────────────────────────────────────────────

  Color _planColor() {
    switch (masterLeague.plan) {
      case MasterLeaguePlan.elite:
        return const Color(0xFF8B5CF6);
      case MasterLeaguePlan.pro:
        return const Color(0xFF22C55E);
      case MasterLeaguePlan.basic:
      default:
        return AppTheme.limeAccentDark;
    }
  }

  // ── Status pill ───────────────────────────────────────────────────────────
  // Context NOT passed — reads Theme internally.
  // BuildContext removed from signature (was unused in original).

  Widget _statusPill({
    required Brightness brightness,
    required String     text,
    required Color      color,
    IconData?           icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border:       Border.all(
            color: color.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color:      color,
              fontWeight: FontWeight.w900,
              fontSize:   11,
            ),
          ),
        ],
      ),
    );
  }

  // ── Banner ────────────────────────────────────────────────────────────────

  Widget _bannerPreview(Brightness brightness) {
    final url = masterLeague
        .organizerProfile.bannerUrl.trim();

    if (url.isEmpty) {
      return _EmptyBanner(brightness: brightness);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        // Clean — no Cloudinary logic in this widget
        CloudinaryUtils.fill(url, width: 1000, height: 280),
        height:          132,
        width:           double.infinity,
        fit:             BoxFit.cover,
        filterQuality:   FilterQuality.low,
        errorBuilder:    (_, __, ___) =>
            _EmptyBanner(brightness: brightness),
      ),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────

  Widget _logo(Brightness brightness) {
    final logoUrl = masterLeague
        .organizerProfile.logoUrl.trim();

    return Container(
      width:  58,
      height: 58,
      decoration: BoxDecoration(
        shape:  BoxShape.circle,
        color:  AppTheme.iconCircleBackground(brightness),
        border: Border.all(
            color: AppTheme.cardBorder(brightness)),
      ),
      child: ClipOval(
        child: logoUrl.isEmpty
            ? Icon(
                Icons.hub_rounded,
                color: AppTheme.limeAccentDark,
                size:  28,
              )
            : Image.network(
                // Clean — thumb variant for circular logo
                CloudinaryUtils.thumb(
                    logoUrl, size: 180),
                fit:           BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder:  (_, __, ___) => Icon(
                  Icons.hub_rounded,
                  color: AppTheme.limeAccentDark,
                  size:  28,
                ),
              ),
      ),
    );
  }

  // ── Meta text chip ────────────────────────────────────────────────────────

  Widget _metaText(
    Brightness brightness, {
    required IconData icon,
    required String   text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size:  14,
            color: AppTheme.limeAccentDark),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color:      AppTheme.secondaryText(brightness),
            fontWeight: FontWeight.w700,
            fontSize:   11.5,
          ),
        ),
      ],
    );
  }

  // ── Hero body — shared between both render styles ─────────────────────────

  Widget _buildHero(Brightness brightness) {
    final planColor  = _planColor();
    final isVerified = masterLeague.isVerifiedOrganizer;
    final isPending  = masterLeague.isVerificationPending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner
        _bannerPreview(brightness),
        const SizedBox(height: 14),

        // Logo + Name row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _logo(brightness),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // Name + verified icon
                  Wrap(
                    spacing:             8,
                    runSpacing:          8,
                    crossAxisAlignment:
                        WrapCrossAlignment.center,
                    children: [
                      Text(
                        masterLeague.name.trim().isEmpty
                            ? 'Master League'
                            : masterLeague.name.trim(),
                        style: const TextStyle(
                          fontWeight:   FontWeight.w900,
                          letterSpacing: -0.3,
                          fontSize:     16,
                        ),
                      ),
                      if (isVerified)
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF1D9BF0),
                          size:  18,
                        )
                      else if (isPending)
                        const Icon(
                          Icons.verified_outlined,
                          color: Color(0xFFF59E0B),
                          size:  18,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Status pills
                  Wrap(
                    spacing:    8,
                    runSpacing: 8,
                    children: [
                      _statusPill(
                        brightness: brightness,
                        text:       masterLeague
                            .plan.displayName,
                        color: planColor,
                        icon:  Icons
                            .workspace_premium_rounded,
                      ),
                      if (masterLeague.organizerProfile
                          .badge
                          .trim()
                          .isNotEmpty)
                        _statusPill(
                          brightness: brightness,
                          text: masterLeague
                              .organizerProfile.badge
                              .trim(),
                          color: const Color(0xFFF59E0B),
                        ),
                      _statusPill(
                        brightness: brightness,
                        text:
                            '${masterLeague.followersCount}'
                            ' follower'
                            '${masterLeague.followersCount == 1 ? '' : 's'}',
                        color: const Color(0xFF22C55E),
                        icon:
                            Icons.favorite_border_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Bio
        Text(
          masterLeague.organizerProfile.bio
                  .trim()
                  .isEmpty
              ? 'No organizer bio yet.'
              : masterLeague.organizerProfile.bio.trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:      AppTheme.secondaryText(brightness),
            height:     1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Analytics row
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing:    10,
                runSpacing: 8,
                children: [
                  _metaText(
                    brightness,
                    icon: Icons.emoji_events_outlined,
                    text: '${masterLeague.analytics.totalTournamentsCreated}'
                        ' competitions',
                  ),
                  _metaText(
                    brightness,
                    icon: Icons.groups_rounded,
                    text: '${masterLeague.analytics.totalParticipantsTeams}'
                        ' teams',
                  ),
                  _metaText(
                    brightness,
                    icon: Icons.sports_score_rounded,
                    text: '${masterLeague.analytics.totalMatches}'
                        ' matches',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.secondaryText(brightness),
            ),
          ],
        ),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // LayoutBuilder reads the card's OWN available width.
    // This is correct regardless of screen size, sidebar width,
    // or how the parent lays out this widget.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop =
            constraints.maxWidth >= _BP.desktop;

        final hero = _buildHero(brightness);

        if (isDesktop) {
          // Desktop / web style:
          // Flat container — no Glass blur layer.
          // Reason: backdrop-filter (Glass) on web causes
          // significant compositing cost when many cards
          // are visible simultaneously in a grid.
          return Material(
            color:        Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap:        onTap,
              child: Container(
                decoration: BoxDecoration(
                  color:        AppTheme.cardColor(brightness),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color:
                          AppTheme.cardBorder(brightness)),
                ),
                padding: const EdgeInsets.all(16),
                child:   hero,
              ),
            ),
          );
        }

        // Mobile style: Glass blur effect
        return Glass(
          borderRadius: 22,
          padding:      const EdgeInsets.all(16),
          fill:         AppTheme.cardColor(brightness),
          borderColor:  AppTheme.cardBorder(brightness),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap:        onTap,
              child:        hero,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _EmptyBanner — extracted to avoid rebuilding inline on every render
// ---------------------------------------------------------------------------

class _EmptyBanner extends StatelessWidget {
  const _EmptyBanner({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color:        AppTheme.searchBackground(brightness),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppTheme.searchOutline(brightness)),
      ),
      child: Center(
        child: Icon(
          Icons.photo_size_select_actual_outlined,
          color: AppTheme.secondaryText(brightness),
          size:  34,
        ),
      ),
    );
  }
}
