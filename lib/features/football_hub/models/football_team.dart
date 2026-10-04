// lib/features/football_hub/models/football_team.dart

/// A team entry from API-Football's /teams endpoint -- used for the
/// Football Hub's team search.
class FootballTeam {
  final int id;
  final String name;
  final String logoUrl;
  final String countryName;
  final int founded;
  final bool national;

  const FootballTeam({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.countryName,
    required this.founded,
    required this.national,
  });

  factory FootballTeam.fromJson(Map<String, dynamic> json) {
    final team = (json['team'] as Map?)?.cast<String, dynamic>() ?? const {};

    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    String toStr(dynamic v) => (v ?? '').toString();
    bool toBool(dynamic v) => v == true;

    return FootballTeam(
      id: toInt(team['id']),
      name: toStr(team['name']),
      logoUrl: toStr(team['logo']),
      countryName: toStr(team['country']),
      founded: toInt(team['founded']),
      national: toBool(team['national']),
    );
  }
}
