// lib/features/football_hub/models/football_player.dart

/// A single entry from API-Football's /players/squads endpoint -- just
/// enough for a squad list row (no stats; stats need a separate /players
/// call per player, which is why FootballPlayerProfile is a distinct type).
class FootballSquadPlayer {
  final int id;
  final String name;
  final int age;
  final int? number;
  final String position;
  final String photoUrl;

  const FootballSquadPlayer({
    required this.id,
    required this.name,
    required this.age,
    required this.number,
    required this.position,
    required this.photoUrl,
  });

  factory FootballSquadPlayer.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    int? toIntOrNull(dynamic v) =>
        v == null ? null : (v is int ? v : (v is num ? v.toInt() : int.tryParse('$v')));
    String toStr(dynamic v) => (v ?? '').toString();

    return FootballSquadPlayer(
      id: toInt(json['id']),
      name: toStr(json['name']),
      age: toInt(json['age']),
      number: toIntOrNull(json['number']),
      position: toStr(json['position']),
      photoUrl: toStr(json['photo']),
    );
  }
}

/// A player's bio + aggregated season stats, from API-Football's /players
/// endpoint (id+season). Stats are summed across every competition entry
/// the API returns for that season (league + cup + continental all count
/// toward "season stats" here, same as how a fan would describe a
/// player's season) -- NOT just the first/primary competition.
class FootballPlayerProfile {
  final int id;
  final String name;
  final String photoUrl;
  final int age;
  final String nationality;
  final int? heightCm;
  final int? weightKg;
  final String primaryPosition;
  final String primaryTeamName;
  final String primaryTeamLogoUrl;

  final int appearances;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final double? averageRating;

  const FootballPlayerProfile({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.age,
    required this.nationality,
    required this.heightCm,
    required this.weightKg,
    required this.primaryPosition,
    required this.primaryTeamName,
    required this.primaryTeamLogoUrl,
    required this.appearances,
    required this.goals,
    required this.assists,
    required this.yellowCards,
    required this.redCards,
    required this.averageRating,
  });

  static int? _parseLeadingInt(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  factory FootballPlayerProfile.fromApiResponseEntry(Map<String, dynamic> json) {
    final player = (json['player'] as Map?)?.cast<String, dynamic>() ?? const {};
    final statsList = (json['statistics'] as List?)?.whereType<Map>().toList() ?? const [];

    int toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    String toStr(dynamic v) => (v ?? '').toString();

    int appearances = 0, goals = 0, assists = 0, yellow = 0, red = 0;
    final ratings = <double>[];
    String primaryPosition = '';
    String primaryTeamName = '';
    String primaryTeamLogoUrl = '';

    for (var i = 0; i < statsList.length; i++) {
      final s = statsList[i].cast<String, dynamic>();
      final games = (s['games'] as Map?)?.cast<String, dynamic>() ?? const {};
      final goalsMap = (s['goals'] as Map?)?.cast<String, dynamic>() ?? const {};
      final cards = (s['cards'] as Map?)?.cast<String, dynamic>() ?? const {};
      final team = (s['team'] as Map?)?.cast<String, dynamic>() ?? const {};

      appearances += toInt(games['appearences']);
      goals += toInt(goalsMap['total']);
      assists += toInt(goalsMap['assists']);
      yellow += toInt(cards['yellow']);
      red += toInt(cards['red']);

      final ratingStr = toStr(games['rating']);
      final rating = double.tryParse(ratingStr);
      if (rating != null) ratings.add(rating);

      if (i == 0) {
        primaryPosition = toStr(games['position']);
        primaryTeamName = toStr(team['name']);
        primaryTeamLogoUrl = toStr(team['logo']);
      }
    }

    final birth = (player['birth'] as Map?)?.cast<String, dynamic>() ?? const {};

    return FootballPlayerProfile(
      id: toInt(player['id']),
      name: toStr(player['name']),
      photoUrl: toStr(player['photo']),
      age: toInt(player['age']),
      nationality: toStr(player['nationality']).isNotEmpty
          ? toStr(player['nationality'])
          : toStr(birth['country']),
      heightCm: _parseLeadingInt(toStr(player['height'])),
      weightKg: _parseLeadingInt(toStr(player['weight'])),
      primaryPosition: primaryPosition,
      primaryTeamName: primaryTeamName,
      primaryTeamLogoUrl: primaryTeamLogoUrl,
      appearances: appearances,
      goals: goals,
      assists: assists,
      yellowCards: yellow,
      redCards: red,
      averageRating: ratings.isEmpty ? null : ratings.reduce((a, b) => a + b) / ratings.length,
    );
  }
}
