// lib/features/football_hub/models/football_league.dart

/// A league/competition entry from API-Football's /leagues endpoint --
/// used for the Leagues tab's search/browse list.
class FootballLeagueInfo {
  final int id;
  final String name;
  final String type; // "League" or "Cup"
  final String logoUrl;
  final String countryName;
  final String countryFlagUrl;
  final int currentSeason;

  const FootballLeagueInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.logoUrl,
    required this.countryName,
    required this.countryFlagUrl,
    required this.currentSeason,
  });

  factory FootballLeagueInfo.fromJson(Map<String, dynamic> json) {
    final league = (json['league'] as Map?)?.cast<String, dynamic>() ?? const {};
    final country = (json['country'] as Map?)?.cast<String, dynamic>() ?? const {};
    final seasons = (json['seasons'] as List?)?.whereType<Map>().toList() ?? const [];

    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    String toStr(dynamic v) => (v ?? '').toString();

    // Prefer the season marked current:true; fall back to the latest year.
    Map? currentSeason = seasons.cast<Map?>().firstWhere(
          (s) => s?['current'] == true,
          orElse: () => null,
        );
    if (currentSeason == null && seasons.isNotEmpty) {
      final sorted = [...seasons]
        ..sort((a, b) => toInt(b['year']).compareTo(toInt(a['year'])));
      currentSeason = sorted.first;
    }

    return FootballLeagueInfo(
      id: toInt(league['id']),
      name: toStr(league['name']),
      type: toStr(league['type']),
      logoUrl: toStr(league['logo']),
      countryName: toStr(country['name']),
      countryFlagUrl: toStr(country['flag']),
      currentSeason: toInt(currentSeason?['year']),
    );
  }
}
