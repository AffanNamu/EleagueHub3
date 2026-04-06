import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';

class FixtureCard extends StatelessWidget {
  const FixtureCard({
    super.key,
    required this.home,
    required this.away,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.isPlayed = false,
  });

  final String home;
  final String away;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;
  final bool isPlayed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final t = theme.textTheme;

    final titleColor = isPlayed
        ? AppTheme.secondaryText(brightness)
        : AppTheme.primaryText(brightness);
    final subtitleColor = AppTheme.secondaryText(brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Glass(
        borderRadius: 20,
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$home vs $away',
                          style: t.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: t.bodySmall?.copyWith(
                            color: subtitleColor,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
