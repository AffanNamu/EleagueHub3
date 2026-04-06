import 'package:flutter/material.dart';

import '../core/locale/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/glass.dart';

class AdminScoreCard extends StatefulWidget {
  final String homeTeam;
  final String awayTeam;
  final Function(int, int) onSave;

  const AdminScoreCard({
    super.key,
    required this.homeTeam,
    required this.awayTeam,
    required this.onSave,
  });

  @override
  State<AdminScoreCard> createState() => _AdminScoreCardState();
}

class _AdminScoreCardState extends State<AdminScoreCard> {
  int homeScore = 0;
  int awayScore = 0;

  Widget _scoreCounter(
    BuildContext context, {
    required String label,
    required int score,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final primaryText = AppTheme.primaryText(brightness);
    final secondaryText = AppTheme.secondaryText(brightness);

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.searchBackground(brightness),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.searchOutline(brightness)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.remove_circle_outline, color: AppTheme.limeAccentDark),
                onPressed: score > 0 ? () => onChanged(score - 1) : null,
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '$score',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: primaryText,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: AppTheme.limeAccentDark),
                onPressed: () => onChanged(score + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: Text(
                  widget.homeTeam,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                l10n.tr('match_detail_vs').toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppTheme.limeAccentDark,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              Expanded(
                child: Text(
                  widget.awayTeam,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.primaryText(brightness),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _scoreCounter(
                context,
                label: l10n.tr('admin_score_home_fallback').toUpperCase(),
                score: homeScore,
                onChanged: (val) => setState(() => homeScore = val),
              ),
              _scoreCounter(
                context,
                label: l10n.tr('admin_score_away_fallback').toUpperCase(),
                score: awayScore,
                onChanged: (val) => setState(() => awayScore = val),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () => widget.onSave(homeScore, awayScore),
              child: Text(
                l10n.tr('admin_score_card_update_score').toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
