import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../../auth/data/user_profile_repository.dart';
import '../../../auth/models/user_profile.dart';
import '../../domain/master_league.dart';

class MasterLeagueCard extends StatelessWidget {
  const MasterLeagueCard({
    super.key,
    required this.masterLeague,
    required this.onTap,
  });

  final MasterLeague masterLeague;
  final VoidCallback onTap;

  String _createdLabel() {
    final ts = masterLeague.createdAt;
    if (ts == null) return '';
    try {
      final dt = ts.toDate().toLocal();
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      return '${dt.year}-$month-$day';
    } catch (_) {
      return '';
    }
  }

  String _safeNetworkImage(String url) {
    final value = url.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final currentUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final isOwner =
        currentUid.isNotEmpty && masterLeague.ownerId.trim() == currentUid;

    final title = masterLeague.name.trim().isEmpty
        ? 'Master League'
        : masterLeague.name.trim();

    final bio = masterLeague.organizerProfile.bio.trim();
    final badge = masterLeague.organizerProfile.badge.trim();
    final created = _createdLabel();
    final initialCompetition = masterLeague.initialCompetition;

    final subtitle =
        masterLeague.isActive ? 'Organizer workspace' : 'Inactive organizer workspace';

    final rewardsText = initialCompetition == null
        ? ''
        : initialCompetition.rewardsPlan.trim();

    final organizerLogoUrl =
        _safeNetworkImage(masterLeague.organizerProfile.logoUrl);

    return FutureBuilder<UserProfile?>(
      future: UserProfileRepository().fetchByUserId(masterLeague.ownerId),
      builder: (context, ownerSnap) {
        final ownerProfile = ownerSnap.data;
        final ownerImageUrl =
            _safeNetworkImage(ownerProfile?.effectivePhotoUrl ?? '');
        final effectiveAvatarUrl =
            organizerLogoUrl.isNotEmpty ? organizerLogoUrl : ownerImageUrl;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Glass(
            borderRadius: 24,
            padding: EdgeInsets.zero,
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: AppTheme.leagueCardGradient(brightness),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.iconCircleBackground(brightness),
                        backgroundImage: effectiveAvatarUrl.isNotEmpty
                            ? NetworkImage(effectiveAvatarUrl)
                            : null,
                        child: effectiveAvatarUrl.isEmpty
                            ? Icon(
                                Icons.hub_rounded,
                                color: AppTheme.limeAccentDark,
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
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
                                  title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppTheme.primaryText(brightness),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                _chip(
                                  theme: theme,
                                  brightness: brightness,
                                  color: masterLeague.isActive
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFF59E0B),
                                  label: masterLeague.isActive
                                      ? 'ACTIVE'
                                      : 'INACTIVE',
                                ),
                                _chip(
                                  theme: theme,
                                  brightness: brightness,
                                  color: AppTheme.limeAccentDark,
                                  label: masterLeague.plan.displayName.toUpperCase(),
                                ),
                                _chip(
                                  theme: theme,
                                  brightness: brightness,
                                  color: isOwner
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF8B5CF6),
                                  label: isOwner ? 'OWNER' : 'VISITOR',
                                ),
                                if (masterLeague.isVerifiedOrganizer)
                                  _chip(
                                    theme: theme,
                                    brightness: brightness,
                                    color: const Color(0xFF1D9BF0),
                                    label: 'VERIFIED',
                                  ),
                                if (masterLeague.isVerificationPending)
                                  _chip(
                                    theme: theme,
                                    brightness: brightness,
                                    color: const Color(0xFFF59E0B),
                                    label: 'PENDING REVIEW',
                                  ),
                                if (badge.isNotEmpty)
                                  _chip(
                                    theme: theme,
                                    brightness: brightness,
                                    color: const Color(0xFFF59E0B),
                                    label: badge.toUpperCase(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondaryText(brightness),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    bio.isEmpty ? 'No organizer bio added yet.' : bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (initialCompetition != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: brightness == Brightness.dark
                            ? AppTheme.limeAccentDark.withOpacity(0.12)
                            : const Color(0xFFECFCCB),
                        border: Border.all(
                          color: brightness == Brightness.dark
                              ? AppTheme.limeAccentDark.withOpacity(0.22)
                              : const Color(0xFFD9F99D),
                        ),
                      ),
                      child: Text(
                        rewardsText.isEmpty
                            ? 'First competition: ${initialCompetition.name}'
                            : 'First competition: ${initialCompetition.name} • Rewards: $rewardsText',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _stat(
                        context,
                        '${masterLeague.analytics.totalParticipantsTeams} teams',
                      ),
                      _stat(
                        context,
                        '${masterLeague.followersCount} followers',
                      ),
                      if (created.isNotEmpty) _stat(context, 'Created $created'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: AppTheme.limeAccent,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.dashboard_customize_outlined,
                                size: 18,
                                color: AppTheme.darkText,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Open Workspace',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: AppTheme.darkText,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
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
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip({
    required ThemeData theme,
    required Brightness brightness,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: brightness == Brightness.dark
            ? color.withOpacity(0.14)
            : color.withOpacity(0.10),
        border: Border.all(
          color: brightness == Brightness.dark
              ? color.withOpacity(0.28)
              : color.withOpacity(0.22),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String text) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppTheme.searchBackground(brightness),
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
