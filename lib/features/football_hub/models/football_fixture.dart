// lib/features/football_hub/models/football_fixture.dart

/// A single match returned by API-Football's /fixtures endpoint.
///
/// Parsing is defensive (every field has a safe default) because this data
/// comes from a third-party upstream API this app does not control -- an
/// unexpected null/missing field must never crash the Matches tab.
class FootballFixture {
  final int id;
  final DateTime kickoff;
  final String statusShort; // e.g. "NS" (not started), "1H", "HT", "FT", "PEN"
  final String statusLong;
  final int? elapsedMinutes;

  final int leagueId;
  final String leagueName;
  final String leagueLogoUrl;
  final String leagueCountry;
  final String round;
  final int season;

  final int homeTeamId;
  final String homeTeamName;
  final String homeTeamLogoUrl;
  final int awayTeamId;
  final String awayTeamName;
  final String awayTeamLogoUrl;

  final int? homeGoals;
  final int? awayGoals;

  const FootballFixture({
    required this.id,
    required this.kickoff,
    required this.statusShort,
    required this.statusLong,
    required this.elapsedMinutes,
    required this.leagueId,
    required this.leagueName,
    required this.leagueLogoUrl,
    required this.leagueCountry,
    required this.round,
    required this.season,
    required this.homeTeamId,
    required this.homeTeamName,
    required this.homeTeamLogoUrl,
    required this.awayTeamId,
    required this.awayTeamName,
    required this.awayTeamLogoUrl,
    required this.homeGoals,
    required this.awayGoals,
  });

  bool get isLive => const {'1H', '2H', 'HT', 'ET', 'P', 'BT'}.contains(statusShort);
  bool get isFinished => const {'FT', 'AET', 'PEN'}.contains(statusShort);
  bool get isUpcoming => !isLive && !isFinished;

  factory FootballFixture.fromJson(Map<String, dynamic> json) {
    final fixture = (json['fixture'] as Map?)?.cast<String, dynamic>() ?? const {};
    final league = (json['league'] as Map?)?.cast<String, dynamic>() ?? const {};
    final teams = (json['teams'] as Map?)?.cast<String, dynamic>() ?? const {};
    final home = (teams['home'] as Map?)?.cast<String, dynamic>() ?? const {};
    final away = (teams['away'] as Map?)?.cast<String, dynamic>() ?? const {};
    final goals = (json['goals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final status = (fixture['status'] as Map?)?.cast<String, dynamic>() ?? const {};

    DateTime kickoff;
    final tsRaw = fixture['timestamp'];
    if (tsRaw is int) {
      kickoff = DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000, isUtc: true).toLocal();
    } else {
      final dateStr = (fixture['date'] as String? ?? '').trim();
      kickoff = DateTime.tryParse(dateStr)?.toLocal() ?? DateTime.now();
    }

    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    int? toIntOrNull(dynamic v) =>
        v == null ? null : (v is int ? v : (v is num ? v.toInt() : int.tryParse('$v')));
    String toStr(dynamic v) => (v ?? '').toString();

    return FootballFixture(
      id: toInt(fixture['id']),
      kickoff: kickoff,
      statusShort: toStr(status['short']),
      statusLong: toStr(status['long']),
      elapsedMinutes: toIntOrNull(status['elapsed']),
      leagueId: toInt(league['id']),
      leagueName: toStr(league['name']),
      leagueLogoUrl: toStr(league['logo']),
      leagueCountry: toStr(league['country']),
      round: toStr(league['round']),
      season: toInt(league['season']),
      homeTeamId: toInt(home['id']),
      homeTeamName: toStr(home['name']),
      homeTeamLogoUrl: toStr(home['logo']),
      awayTeamId: toInt(away['id']),
      awayTeamName: toStr(away['name']),
      awayTeamLogoUrl: toStr(away['logo']),
      homeGoals: toIntOrNull(goals['home']),
      awayGoals: toIntOrNull(goals['away']),
    );
  }
}
