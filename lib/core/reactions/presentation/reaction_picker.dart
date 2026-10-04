// lib/core/reactions/presentation/reaction_picker.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../message_reaction.dart';

/// Shows the fixed emoji palette in a compact bottom sheet and resolves
/// with the picked emoji, or null if dismissed without a pick. Pass
/// [currentEmoji] (the caller's existing reaction, if any) to highlight it
/// -- tapping it again lets the caller remove their reaction.
Future<String?> showReactionPicker(
  BuildContext context, {
  String? currentEmoji,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final brightness = Theme.of(sheetContext).brightness;
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.cardColor(brightness),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.cardBorder(brightness)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final emoji in kReactionEmojis)
                _EmojiButton(
                  emoji: emoji,
                  selected: emoji == currentEmoji,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(sheetContext).pop(emoji);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.limeAccentDark.withOpacity(0.18)
              : Colors.transparent,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: AppTheme.limeAccentDark.withOpacity(0.65))
              : null,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}
