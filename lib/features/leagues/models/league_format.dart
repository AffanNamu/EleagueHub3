enum LeagueFormat {
  classic,
  uclGroup,
  uclSwiss;

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
    }
  }
}

extension LeagueFormatX on LeagueFormat {
  static LeagueFormat fromInt(int v) {
    if (v < 0 || v >= LeagueFormat.values.length) return LeagueFormat.classic;
    return LeagueFormat.values[v];
  }
}
