import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/league_mode_provider.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

class LeagueSwitcher extends ConsumerWidget {
  const LeagueSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final currentMode = ref.watch(leagueModeProvider);

    return Glass(
      padding: const EdgeInsets.all(6),
      borderRadius: 22,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        children: LeagueType.values.map((type) {
          final isSelected = currentMode == type;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                ref.read(leagueModeProvider.notifier).state = type;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.limeAccent
                      : AppTheme.tabInactiveBackground(brightness),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _label(type),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isSelected
                        ? AppTheme.darkText
                        : AppTheme.tabInactiveText(brightness),
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(LeagueType type) {
    switch (type) {
      case LeagueType.classic:
        return 'CLASSIC';
      case LeagueType.uclClassic:
        return 'UCL';
      case LeagueType.uclSwiss:
        return 'SWISS';
    }
  }
}
