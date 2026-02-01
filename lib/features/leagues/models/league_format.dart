enum LeagueFormat {
  classic,
  uclGroup,
  uclSwiss;

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
}

extension LeagueFormatX on LeagueFormat {
  static LeagueFormat fromInt(int v) {
    if (v < 0 || v >= LeagueFormat.values.length) return LeagueFormat.classic;
    return LeagueFormat.values[v];
  }
}
