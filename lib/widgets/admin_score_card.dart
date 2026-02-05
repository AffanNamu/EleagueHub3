import 'package:flutter/material.dart';

import '../core/locale/app_localizations.dart';
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
    final cs = theme.colorScheme;

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.72),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.remove_circle_outline, color: cs.primary),
              onPressed: score > 0 ? () => onChanged(score - 1) : null,
            ),
            Text(
              '$score',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: cs.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: cs.primary),
              onPressed: () => onChanged(score + 1),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
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
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                l10n.tr('match_detail_vs').toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              Expanded(
                child: Text(
                  widget.awayTeam,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onSave(homeScore, awayScore),
              child: Text(l10n.tr('admin_score_card_update_score').toUpperCase()),
            ),
          ),
        ],
      ),
    );
  }
}
