// lib/core/reactions/presentation/reaction_pill_bar.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../message_reaction.dart';

/// Row of emoji pills under a message/post showing grouped reaction
/// counts. Tapping a pill the caller already reacted with removes it;
/// tapping another emoji's pill switches to it (one reaction per user).
/// Renders nothing when there are no reactions yet.
class ReactionPillBar extends StatelessWidget {
  const ReactionPillBar({
    super.key,
    required this.summary,
    required this.onTapEmoji,
  });

  final ReactionSummary summary;
  final ValueChanged<String> onTapEmoji;

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in summary.orderedEntries)
            _ReactionPill(
              emoji: entry.key,
              count: entry.value,
              isMine: summary.myEmoji == entry.key,
              brightness: brightness,
              onTap: () => onTapEmoji(entry.key),
            ),
        ],
      ),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.brightness,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool isMine;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isMine
              ? AppTheme.limeAccentDark.withOpacity(0.18)
              : AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isMine
                ? AppTheme.limeAccentDark.withOpacity(0.65)
                : AppTheme.searchOutline(brightness),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isMine
                    ? AppTheme.limeAccentDark
                    : AppTheme.secondaryText(brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
