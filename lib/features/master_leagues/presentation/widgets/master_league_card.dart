import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../domain/master_league.dart';
import '../../domain/master_league_plan.dart';

class MasterLeagueCard extends StatelessWidget {
  const MasterLeagueCard({
    super.key,
    required this.masterLeague,
    this.onTap,
  });

  final MasterLeague masterLeague;
  final VoidCallback? onTap;

  String _cloudinaryOptimizedUrl(
    String url, {
    int? width,
    int? height,
    String crop = 'fill',
  }) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final isCloudinary =
        u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;
    const marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms = <String>[
      'f_auto',
      'q_auto',
      if (width != null && width > 0) 'w_$width',
      if (height != null && height > 0) 'h_$height',
      (crop == 'fit') ? 'c_fit' : 'c_fill',
      if (crop != 'fit') 'g_auto',
    ].join(',');

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly =
        first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

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

  Widget _statusPill(
    BuildContext context, {
    required String text,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
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
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerPreview(Brightness brightness) {
    final url = masterLeague.organizerProfile.bannerUrl.trim();
    if (url.isEmpty) {
      return Container(
        height: 132,
        decoration: BoxDecoration(
          color: AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.searchOutline(brightness)),
        ),
        child: Center(
          child: Icon(
            Icons.photo_size_select_actual_outlined,
            color: AppTheme.secondaryText(brightness),
            size: 34,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        _cloudinaryOptimizedUrl(
          url,
          width: 1000,
          height: 280,
          crop: 'fill',
        ),
        height: 132,
        width: double.infinity,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => Container(
          height: 132,
          decoration: BoxDecoration(
            color: AppTheme.searchBackground(brightness),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.searchOutline(brightness)),
          ),
          alignment: Alignment.center,
          child: Text(
            'Banner unavailable',
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo(Brightness brightness) {
    final logoUrl = masterLeague.organizerProfile.logoUrl.trim();

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.iconCircleBackground(brightness),
        border: Border.all(color: AppTheme.cardBorder(brightness)),
      ),
      child: ClipOval(
        child: logoUrl.isEmpty
            ? Icon(
                Icons.hub_rounded,
                color: AppTheme.limeAccentDark,
                size: 28,
              )
            : Image.network(
                _cloudinaryOptimizedUrl(
                  logoUrl,
                  width: 180,
                  height: 180,
                  crop: 'fill',
                ),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.hub_rounded,
                  color: AppTheme.limeAccentDark,
                  size: 28,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final planColor = _planColor();
    final isVerified = masterLeague.isVerifiedOrganizer;
    final isPending = masterLeague.isVerificationPending;

    final hero = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bannerPreview(brightness),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _logo(brightness),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        masterLeague.name.trim().isEmpty
                            ? 'Master League'
                            : masterLeague.name.trim(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      if (isVerified)
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF1D9BF0),
                          size: 18,
                        )
                      else if (isPending)
                        const Icon(
                          Icons.verified_outlined,
                          color: Color(0xFFF59E0B),
                          size: 18,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusPill(
                        context,
                        text: masterLeague.plan.displayName,
                        color: planColor,
                        icon: Icons.workspace_premium_rounded,
                      ),
                      if (masterLeague.organizerProfile.badge
                          .trim()
                          .isNotEmpty)
                        _statusPill(
                          context,
                          text: masterLeague.organizerProfile.badge.trim(),
                          color: const Color(0xFFF59E0B),
                        ),
                      _statusPill(
                        context,
                        text:
                            '${masterLeague.followersCount} follower${masterLeague.followersCount == 1 ? '' : 's'}',
                        color: const Color(0xFF22C55E),
                        icon: Icons.favorite_border_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          masterLeague.organizerProfile.bio.trim().isEmpty
              ? 'No organizer bio yet.'
              : masterLeague.organizerProfile.bio.trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.secondaryText(brightness),
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _metaText(
                    brightness,
                    icon: Icons.emoji_events_outlined,
                    text:
                        '${masterLeague.analytics.totalTournamentsCreated} competitions',
                  ),
                  _metaText(
                    brightness,
                    icon: Icons.groups_rounded,
                    text:
                        '${masterLeague.analytics.totalParticipantsTeams} teams',
                  ),
                  _metaText(
                    brightness,
                    icon: Icons.sports_score_rounded,
                    text: '${masterLeague.analytics.totalMatches} matches',
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

    final isWebWide = MediaQuery.of(context).size.width >= 900;

    if (isWebWide) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardColor(brightness),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.cardBorder(brightness)),
            ),
            padding: const EdgeInsets.all(16),
            child: hero,
          ),
        ),
      );
    }

    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: hero,
        ),
      ),
    );
  }

  Widget _metaText(
    Brightness brightness, {
    required IconData icon,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.limeAccentDark),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: AppTheme.secondaryText(brightness),
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}
