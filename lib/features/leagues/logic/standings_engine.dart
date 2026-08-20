///leagues/logic/Standings_engine.dart
import '../models/team_stats.dart';
import '../models/fixture_match.dart';

/// Sorts teams into a deterministic league table order using TeamStats.
///
/// Tie-breakers applied (must match StandingsCalculator behavior):
/// 1) Points (descending)
/// 2) Head-to-head points (descending)
/// 3) Goal difference (descending)
/// 4) Goals for (descending)
/// 5) TeamId (ascending) as stable final fallback
class StandingsEngine {
  static List<TeamStats> compute(
    List<TeamStats> teams,
    List<FixtureMatch> matches,
  ) {
    final sorted = List<TeamStats>.from(teams);

    sorted.sort((a, b) {
      if (a.points != b.points) {
        return b.points.compareTo(a.points);
      }

      final h2h = _headToHeadCompare(a, b, matches);
      if (h2h != 0) return h2h;

      if (a.goalDifference != b.goalDifference) {
        return b.goalDifference.compareTo(a.goalDifference);
      }

      if (a.goalsFor != b.goalsFor) {
        return b.goalsFor.compareTo(a.goalsFor);
      }

      // Stable deterministic fallback (matches StandingsCalculator)
      return a.teamId.compareTo(b.teamId);
    });

    return sorted;
  }

  /// Head-to-head points-only comparison between two teams.
  static int _headToHeadCompare(
    TeamStats a,
    TeamStats b,
    List<FixtureMatch> matches,
  ) {
    int aPoints = 0;
    int bPoints = 0;

    for (final m in matches) {
      if (!m.isPlayed) continue;

      final isRelevant =
          (m.homeTeamId == a.teamId && m.awayTeamId == b.teamId) ||
          (m.homeTeamId == b.teamId && m.awayTeamId == a.teamId);

      if (!isRelevant) continue;

      final homeGoals = m.homeScore!;
      final awayGoals = m.awayScore!;

      if (homeGoals == awayGoals) {
        aPoints += 1;
        bPoints += 1;
      } else if (homeGoals > awayGoals) {
        if (m.homeTeamId == a.teamId) {
          aPoints += 3;
        } else {
          bPoints += 3;
        }
      } else {
        if (m.awayTeamId == a.teamId) {
          aPoints += 3;
        } else {
          bPoints += 3;
        }
      }
    }

    return bPoints.compareTo(aPoints);
  }
}
