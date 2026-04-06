import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../data/leagues_repository_local.dart';
import '../../models/league.dart';

Future<LeagueJoinMode?> showJoinLeagueModeSheet(
  BuildContext context, {
  required League league,
  String title = 'Join Competition',
}) {
  final theme = Theme.of(context);
  final brightness = theme.brightness;

  Widget tile({
    required IconData icon,
    required String itemTitle,
    required String subtitle,
    required LeagueJoinMode mode,
    required Color tint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(mode),
        borderRadius: BorderRadius.circular(20),
        child: Glass(
          borderRadius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withOpacity(0.12),
                  border: Border.all(color: tint.withOpacity(0.28)),
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.secondaryText(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<LeagueJoinMode>(
    context: context,
    backgroundColor: Colors.transparent,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(14),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Row(
                  children: [
                    Icon(Icons.login_rounded, color: AppTheme.limeAccentDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Glass(
                borderRadius: 20,
                padding: const EdgeInsets.all(14),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      league.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryText(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${league.format.displayName} • ${league.season}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              tile(
                icon: Icons.sports_soccer_rounded,
                itemTitle: 'Join as Participant',
                subtitle:
                    'Register as an active participant inside this league.',
                mode: LeagueJoinMode.participant,
                tint: AppTheme.limeAccentDark,
              ),
              tile(
                icon: Icons.visibility_rounded,
                itemTitle: 'Join as Viewer',
                subtitle:
                    'Add this league to your list without participant membership.',
                mode: LeagueJoinMode.viewer,
                tint: const Color(0xFF8B5CF6),
              ),
            ],
          ),
        ),
      );
    },
  );
}
