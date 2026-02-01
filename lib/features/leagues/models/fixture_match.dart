import 'enums.dart';

class FixtureMatch {
  final String id;
  final String leagueId;
  final String? groupId;
  final int roundNumber;
  final String homeTeamId;
  final String awayTeamId;
  final int? homeScore;
  final int? awayScore;
  final MatchStatus status;
  final int sortIndex;
  final int updatedAtMs;
  final int version;

  FixtureMatch({
    required this.id,
    required this.leagueId,
    this.groupId,
    required this.roundNumber,
    required this.homeTeamId,
    required this.awayTeamId,
    this.homeScore,
    this.awayScore,
    required this.status,
    required this.sortIndex,
    required this.updatedAtMs,
    required this.version,
  });

  /// Considered "played" ONLY when status indicates completion AND both scores exist.
  bool get isPlayed =>
      (status == MatchStatus.completed || status == MatchStatus.played) &&
      homeScore != null &&
      awayScore != null;

  FixtureMatch copyWith({
    int? homeScore,
    int? awayScore,
    MatchStatus? status,
    int? updatedAtMs,
  }) {
    return FixtureMatch(
      id: id,
      leagueId: leagueId,
      groupId: groupId,
      roundNumber: roundNumber,
      homeTeamId: homeTeamId,
      awayTeamId: awayTeamId,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      status: status ?? this.status,
      sortIndex: sortIndex,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      version: version,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'leagueId': leagueId,
        'groupId': groupId,
        'roundNumber': roundNumber,
        'homeTeamId': homeTeamId,
        'awayTeamId': awayTeamId,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'status': status.name,
        'sortIndex': sortIndex,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  factory FixtureMatch.fromJson(Map<String, dynamic> json) => FixtureMatch(
        id: json['id'] as String,
        leagueId: json['leagueId'] as String,
        groupId: json['groupId'] as String?,
        roundNumber: (json['roundNumber'] as num).toInt(),
        homeTeamId: json['homeTeamId'] as String,
        awayTeamId: json['awayTeamId'] as String,
        homeScore: json['homeScore'] as int?,
        awayScore: json['awayScore'] as int?,
        status: MatchStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => MatchStatus.scheduled,
        ),
        sortIndex: (json['sortIndex'] as num).toInt(),
        updatedAtMs: (json['updatedAtMs'] as num).toInt(),
        version: (json['version'] as num).toInt(),
      );
}
