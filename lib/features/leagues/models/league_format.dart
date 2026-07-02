// lib/features/leagues/models/league_format.dart
//
// MODIFIED: Added `worldCup` as index 3.
// Fully backward-compatible — fromInt returns classic for unknown indices.
// Do NOT reorder existing values (classic=0, uclGroup=1, uclSwiss=2).

enum LeagueFormat {
  classic,    // index 0 — Classic League (single round-robin table)
  uclGroup,   // index 1 — Group League (UCL-style groups)
  uclSwiss,   // index 2 — Series League (Swiss system)
  worldCup,   // index 3 — World Cup (32-team FIFA 2022 or 48-team FIFA 2026)
  ;

  /// Legacy (English-only) display name.
  ///
  /// Prefer using [l10nKey] in UI: `context.l10n.tr(format.l10nKey)`.
  String get displayName {
    switch (this) {
      case LeagueFormat.classic:
        return 'Classic League';
      case LeagueFormat.uclGroup:
        return 'Group League';
      case LeagueFormat.uclSwiss:
        return 'Series League';
      case LeagueFormat.worldCup:
        return 'World Cup';
    }
  }

  /// i18n key for displaying this format in UI.
  ///
  /// Usage:
  /// `final name = context.l10n.tr(league.format.l10nKey);`
  String get l10nKey {
    switch (this) {
      case LeagueFormat.classic:
        return 'league_format_classic';
      case LeagueFormat.uclGroup:
        return 'league_format_ucl_group';
      case LeagueFormat.uclSwiss:
        return 'league_format_ucl_swiss';
      case LeagueFormat.worldCup:
        return 'league_format_world_cup';
    }
  }

  /// Whether this format uses a World Cup engine.
  bool get isWorldCup => this == LeagueFormat.worldCup;

  /// Whether this format uses group stages at all.
  bool get hasGroups =>
      this == LeagueFormat.uclGroup || this == LeagueFormat.worldCup;

  /// Whether this format has a knockout bracket.
  bool get hasKnockout =>
      this == LeagueFormat.uclGroup ||
      this == LeagueFormat.uclSwiss ||
      this == LeagueFormat.worldCup;
}

extension LeagueFormatX on LeagueFormat {
  /// Safe deserializer — returns [LeagueFormat.classic] for unknown indices.
  /// IMPORTANT: do NOT change existing index mapping.
  static LeagueFormat fromInt(int v) {
    if (v < 0 || v >= LeagueFormat.values.length) return LeagueFormat.classic;
    return LeagueFormat.values[v];
  }

  /// Safe deserializer from string name (used in some remote payloads).
  static LeagueFormat fromString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return LeagueFormat.classic;
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'worldcup':
      case 'world_cup':
      case 'world cup':
        return LeagueFormat.worldCup;
      case 'uclgroup':
      case 'ucl_group':
      case 'group':
        return LeagueFormat.uclGroup;
      case 'uclswiss':
      case 'ucl_swiss':
      case 'swiss':
      case 'series':
        return LeagueFormat.uclSwiss;
      default:
        return LeagueFormat.classic;
    }
  }
}