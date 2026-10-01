// lib/features/football_hub/models/football_standing.dart

/// One row of a league table, from API-Football's /standings endpoint.
class FootballStandingRow {
  final int rank;
  final int teamId;
  final String teamName;
  final String teamLogoUrl;
  final int points;
  final int goalsDiff;
  final int played;
  final int win;
  final int draw;
  final int lose;
  final int goalsFor;
  final int goalsAgainst;
  final String form; // e.g. "WWDLW", most recent last
  final String description; // e.g. "Promotion - Champions League"

  const FootballStandingRow({
    required this.rank,
    required this.teamId,
    required this.teamName,
    required this.teamLogoUrl,
    required this.points,
    required this.goalsDiff,
    required this.played,
    required this.win,
    required this.draw,
    required this.lose,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.form,
    required this.description,
  });

  factory FootballStandingRow.fromJson(Map<String, dynamic> json) {
    final team = (json['team'] as Map?)?.cast<String, dynamic>() ?? const {};
    final all = (json['all'] as Map?)?.cast<String, dynamic>() ?? const {};
    final allGoals = (all['goals'] as Map?)?.cast<String, dynamic>() ?? const {};

    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    String toStr(dynamic v) => (v ?? '').toString();

    return FootballStandingRow(
      rank: toInt(json['rank']),
      teamId: toInt(team['id']),
      teamName: toStr(team['name']),
      teamLogoUrl: toStr(team['logo']),
      points: toInt(json['points']),
      goalsDiff: toInt(json['goalsDiff']),
      played: toInt(all['played']),
      win: toInt(all['win']),
      draw: toInt(all['draw']),
      lose: toInt(all['lose']),
      goalsFor: toInt(allGoals['for']),
      goalsAgainst: toInt(allGoals['against']),
      form: toStr(json['form']),
      description: toStr(json['description']),
    );
  }
}

/// A full league table: one or more groups of rows (most leagues have a
/// single group; some cup/group-stage competitions have several).
class FootballStandingsTable {
  final int leagueId;
  final String leagueName;
  final String leagueLogoUrl;
  final int season;
  final List<List<FootballStandingRow>> groups;

  const FootballStandingsTable({
    required this.leagueId,
    required this.leagueName,
    required this.leagueLogoUrl,
    required this.season,
    required this.groups,
  });

  /// Convenience accessor for the common single-group case.
  List<FootballStandingRow> get rows => groups.isNotEmpty ? groups.first : const [];

  static FootballStandingsTable? fromApiResponseEntry(Map<String, dynamic> json) {
    final league = (json['league'] as Map?)?.cast<String, dynamic>();
    if (league == null) return null;

    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    String toStr(dynamic v) => (v ?? '').toString();

    final standingsRaw = league['standings'];
    final groups = <List<FootballStandingRow>>[];
    if (standingsRaw is List) {
      for (final group in standingsRaw) {
        if (group is List) {
          groups.add(
            group
                .whereType<Map>()
                .map((e) => FootballStandingRow.fromJson(e.cast<String, dynamic>()))
                .toList(growable: false),
          );
        }
      }
    }

    return FootballStandingsTable(
      leagueId: toInt(league['id']),
      leagueName: toStr(league['name']),
      leagueLogoUrl: toStr(league['logo']),
      season: toInt(league['season']),
      groups: groups,
    );
  }
}
