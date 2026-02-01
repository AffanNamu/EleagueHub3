/// Represents computed statistics for a team within a league.
///
/// This model is:
/// - Derived from FixtureMatch results
/// - Used for standings tables
/// - Deterministic (can be rebuilt anytime from matches)
///
/// IMPORTANT:
/// TeamStats should NEVER be edited manually.
/// It is always recalculated from match results.
class TeamStats {
  final String teamId;
  final String leagueId;

  final int played;
  final int wins;
  final int draws;
  final int losses;

  final int goalsFor;
  final int goalsAgainst;

  /// Cached goal difference (goalsFor - goalsAgainst)
  final int goalDifference;

  /// Total points (Win = 3, Draw = 1, Loss = 0)
  final int points;

  const TeamStats({
    required this.teamId,
    required this.leagueId,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,
    required this.points,
  });

  /// Creates an empty stats record for a team
  /// Used when initializing a league
  factory TeamStats.empty({
    required String teamId,
    required String leagueId,
  }) {
    return TeamStats(
      teamId: teamId,
      leagueId: leagueId,
      played: 0,
      wins: 0,
      draws: 0,
      losses: 0,
      goalsFor: 0,
      goalsAgainst: 0,
      goalDifference: 0,
      points: 0,
    );
  }

  /// Adds a played match result to the stats
  TeamStats applyMatch({
    required int scored,
    required int conceded,
  }) {
    final bool win = scored > conceded;
    final bool draw = scored == conceded;
    final bool loss = scored < conceded;

    return TeamStats(
      teamId: teamId,
      leagueId: leagueId,
      played: played + 1,
      wins: wins + (win ? 1 : 0),
      draws: draws + (draw ? 1 : 0),
      losses: losses + (loss ? 1 : 0),
      goalsFor: goalsFor + scored,
      goalsAgainst: goalsAgainst + conceded,
      goalDifference: (goalsFor + scored) - (goalsAgainst + conceded),
      points: points + (win ? 3 : draw ? 1 : 0),
    );
  }

  /// Merge stats (used in multi-stage formats like UCL or Swiss)
  TeamStats merge(TeamStats other) {
    assert(teamId == other.teamId);
    assert(leagueId == other.leagueId);

    return TeamStats(
      teamId: teamId,
      leagueId: leagueId,
      played: played + other.played,
      wins: wins + other.wins,
      draws: draws + other.draws,
      losses: losses + other.losses,
      goalsFor: goalsFor + other.goalsFor,
      goalsAgainst: goalsAgainst + other.goalsAgainst,
      goalDifference: goalDifference + other.goalDifference,
      points: points + other.points,
    );
  }

  Map<String, dynamic> toMap() => {
        'teamId': teamId,
        'leagueId': leagueId,
        'played': played,
        'wins': wins,
        'draws': draws,
        'losses': losses,
        'goalsFor': goalsFor,
        'goalsAgainst': goalsAgainst,
        'goalDifference': goalDifference,
        'points': points,
      };

  static TeamStats fromMap(Map<String, dynamic> map) {
    return TeamStats(
      teamId: map['teamId'] as String,
      leagueId: map['leagueId'] as String,
      played: (map['played'] as num).toInt(),
      wins: (map['wins'] as num).toInt(),
      draws: (map['draws'] as num).toInt(),
      losses: (map['losses'] as num).toInt(),
      goalsFor: (map['goalsFor'] as num).toInt(),
      goalsAgainst: (map['goalsAgainst'] as num).toInt(),
      goalDifference: (map['goalDifference'] as num).toInt(),
      points: (map['points'] as num).toInt(),
    );
  }
}
