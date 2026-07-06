// lib/features/leagues/models/football_category.dart
//
// Football Category system.
// - Exactly 6 supported categories (do not add more).
// - Backward compatible: missing/unknown Firestore value => Local Football.
// - No migration script required for old league documents.

import 'package:flutter/material.dart';

enum FootballCategory {
  localFootball,
  eFootball,
  eaSportsFC,
  eaSportsFCMobile,
  dreamLeagueSoccer,
  totalFootball,
}

extension FootballCategoryX on FootballCategory {
  /// Exact string stored in Firestore under `footballCategory`.
  String get storageValue {
    switch (this) {
      case FootballCategory.localFootball:
        return 'Local Football';
      case FootballCategory.eFootball:
        return 'eFootball';
      case FootballCategory.eaSportsFC:
        return 'EA SPORTS FC';
      case FootballCategory.eaSportsFCMobile:
        return 'EA SPORTS FC Mobile';
      case FootballCategory.dreamLeagueSoccer:
        return 'Dream League Soccer';
      case FootballCategory.totalFootball:
        return 'Total Football';
    }
  }

  /// Human readable label (same as storage value here).
  String get label => storageValue;

  /// Emoji used for badges, matching the product spec exactly:
  /// ⚽ Local Football
  /// 🎮 eFootball
  /// 🎮 EA SPORTS FC
  /// 📱 EA SPORTS FC Mobile
  /// ⚽ Dream League Soccer
  /// 🎮 Total Football
  String get emoji {
    switch (this) {
      case FootballCategory.localFootball:
        return '⚽';
      case FootballCategory.eFootball:
        return '🎮';
      case FootballCategory.eaSportsFC:
        return '🎮';
      case FootballCategory.eaSportsFCMobile:
        return '📱';
      case FootballCategory.dreamLeagueSoccer:
        return '⚽';
      case FootballCategory.totalFootball:
        return '🎮';
    }
  }

  /// Badge label, e.g. "⚽ Local Football".
  String get badgeLabel => '$emoji $label';

  /// Icon used beside the category in League Details / chips.
  IconData get icon {
    switch (this) {
      case FootballCategory.localFootball:
        return Icons.sports_soccer_rounded;
      case FootballCategory.eFootball:
        return Icons.sports_esports_rounded;
      case FootballCategory.eaSportsFC:
        return Icons.sports_esports_rounded;
      case FootballCategory.eaSportsFCMobile:
        return Icons.phone_iphone_rounded;
      case FootballCategory.dreamLeagueSoccer:
        return Icons.sports_soccer_rounded;
      case FootballCategory.totalFootball:
        return Icons.sports_esports_rounded;
    }
  }
}

class FootballCategoryUtil {
  const FootballCategoryUtil._();

  /// Null-safe parser. Any missing/unrecognized value => Local Football.
  ///
  /// This guarantees old league documents without the `footballCategory`
  /// field automatically behave as Local Football, with NO migration
  /// script required.
  static FootballCategory fromStorage(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return FootballCategory.localFootball;
    for (final c in FootballCategory.values) {
      if (c.storageValue == s) return c;
    }
    return FootballCategory.localFootball;
  }

  /// All supported categories, in the fixed product-spec order.
  static const List<FootballCategory> all = FootballCategory.values;

  /// For filter UI: null represents "All".
  static String filterLabel(FootballCategory? c) =>
      c == null ? 'All' : c.label;
}

// ---------------------------------------------------------------------------
// Reusable UI: selectable chip used on the League Creation screen and on
// the Search & Filter bar. Kept here so both screens share one definition
// and stay visually consistent (uses the app's existing lime accent /
// Material 3 color scheme via Theme.of(context), so it automatically
// supports Light Mode, Dark Mode, and the current app theme).
// ---------------------------------------------------------------------------

class FootballCategoryChip extends StatelessWidget {
  const FootballCategoryChip({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final FootballCategory category;
  final bool selected;
  final VoidCallback? onTap;

  /// Slightly smaller padding/text, used in filter bars.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    final Color accent = scheme.primary;
    final Color bgSelected = accent.withOpacity(
      brightness == Brightness.dark ? 0.22 : 0.14,
    );
    final Color bgUnselected = brightness == Brightness.dark
        ? Colors.white.withOpacity(0.06)
        : const Color(0xFFF3F4F6);
    final Color borderSelected = accent;
    final Color borderUnselected = brightness == Brightness.dark
        ? Colors.white.withOpacity(0.10)
        : const Color(0xFFE5E7EB);
    final Color textSelected =
        brightness == Brightness.dark ? Colors.white : accent;
    final Color textUnselected = brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF6B7280);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 16,
            vertical: dense ? 8 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected ? bgSelected : bgUnselected,
            border: Border.all(
              color: selected ? borderSelected : borderUnselected,
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.emoji,
                style: TextStyle(fontSize: dense ? 13 : 15),
              ),
              const SizedBox(width: 6),
              Text(
                category.label,
                style: TextStyle(
                  color: selected ? textSelected : textUnselected,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: dense ? 12 : 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill used inside League Details to show the selected category,
/// with a football/game icon beside it, matching the "premium badge" look
/// used elsewhere in the app.
class FootballCategoryPill extends StatelessWidget {
  const FootballCategoryPill({
    super.key,
    required this.category,
  });

  final FootballCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: accent.withOpacity(0.10),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            category.label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: accent,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge used on League List cards, e.g. "⚽ Local Football".
class FootballCategoryBadge extends StatelessWidget {
  const FootballCategoryBadge({
    super.key,
    required this.category,
  });

  final FootballCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(category.emoji, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            category.label,
            style: TextStyle(
              color: accent,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}