import 'package:flutter/material.dart';

import '../../../../core/widgets/glass.dart';
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
    final dynamic raw = masterLeague.createdAt;
    DateTime? dt;

    if (raw is DateTime) dt = raw;
    try {
      if (dt == null && raw != null && raw.toDate is Function) {
        final value = raw.toDate();
        if (value is DateTime) dt = value;
      }
    } catch (_) {}

    if (dt == null) return '';

    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = masterLeague.name.trim().isEmpty
        ? 'Master League'
        : masterLeague.name.trim();

    final bio = masterLeague.organizerProfile.bio.trim();
    final badge = masterLeague.organizerProfile.badge.trim();
    final created = _createdLabel();

    final subtitle = masterLeague.isActive
        ? 'Organizer Pro active • Competitions inside included'
        : 'Locked';

    final badgeBg = masterLeague.isActive
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);
    final badgeLabel = masterLeague.isActive ? 'ACTIVE' : 'LOCKED';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Glass(
        borderRadius: 22,
        padding: EdgeInsets.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withOpacity(0.18),
                cs.onSurface.withOpacity(0.03),
              ],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primary.withOpacity(0.12),
                backgroundImage:
                    masterLeague.organizerProfile.logoUrl.trim().isNotEmpty
                        ? NetworkImage(
                            masterLeague.organizerProfile.logoUrl.trim(),
                          )
                        : null,
                child: masterLeague.organizerProfile.logoUrl.trim().isEmpty
                    ? Icon(Icons.hub_rounded, color: cs.primary)
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
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        _chip(
                          theme: theme,
                          color: badgeBg,
                          label: badgeLabel,
                        ),
                        _chip(
                          theme: theme,
                          color: cs.primary,
                          label: masterLeague.plan.displayName.toUpperCase(),
                        ),
                        if (badge.isNotEmpty)
                          _chip(
                            theme: theme,
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
                        color: cs.onSurface.withOpacity(0.60),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bio.isEmpty ? 'No organizer bio added yet.' : bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.72),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _stat(
                          context,
                          '${masterLeague.analytics.totalTournamentsCreated} tournaments',
                        ),
                        _stat(
                          context,
                          '${masterLeague.analytics.totalParticipantsTeams} teams',
                        ),
                        _stat(
                          context,
                          '${masterLeague.analytics.totalMatches} matches',
                        ),
                        _stat(
                          context,
                          '${masterLeague.memberIds.length} staff',
                        ),
                        if (created.isNotEmpty) _stat(context, 'Created $created'),
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
      ),
    );
  }

  Widget _chip({
    required ThemeData theme,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.32)),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.primary.withOpacity(0.06),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
