import 'package:flutter/material.dart';

import '../core/locale/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/glass.dart';

class GlassGroupCard extends StatelessWidget {
  final String title;
  final List<String> teams;

  const GlassGroupCard({super.key, required this.title, required this.teams});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppTheme.limeAccentDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: AppTheme.cardBorder(brightness)),
          const SizedBox(height: 4),
          ...teams.map(
            (team) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: AppTheme.secondaryText(brightness),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      team,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (int i = 0; i < (4 - teams.length); i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                l10n.tr('glass_group_card_empty_slot'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.secondaryText(brightness),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
