import 'package:flutter/material.dart';

class StandingRow extends StatelessWidget {
  final int rank;
  final String teamName;
  final int points;
  final int gd;
  final bool isQualified;

  const StandingRow({
    super.key,
    required this.rank,
    required this.teamName,
    required this.points,
    required this.gd,
    this.isQualified = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bg = isQualified ? cs.primary.withOpacity(0.06) : Colors.transparent;

    final rankStyle = theme.textTheme.bodyMedium?.copyWith(
      color: isQualified ? cs.primary : cs.onSurface.withOpacity(0.65),
      fontWeight: isQualified ? FontWeight.w900 : FontWeight.w700,
    );

    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurface,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    );

    final gdStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withOpacity(0.70),
      fontWeight: FontWeight.w700,
    );

    final ptsStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w900,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: bg,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              style: rankStyle,
            ),
          ),
          Expanded(
            child: Text(
              teamName,
              style: nameStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$gd',
              textAlign: TextAlign.center,
              style: gdStyle,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$points',
              textAlign: TextAlign.center,
              style: ptsStyle,
            ),
          ),
        ],
      ),
    );
  }
}
