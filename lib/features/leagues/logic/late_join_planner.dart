// lib/features/leagues/logic/late_join_planner.dart
//
// PHASE D: safe late-participant join. Pure, Firestore-free decision logic
// -- LocalLeaguesRepository.previewLateJoin()/commitLateJoin() are the only
// callers: they fetch the current league state, ask this planner what the
// operation would look like, and then only ever write exactly what the
// plan says.
//
// Core rule (same one as every earlier phase): a running competition has
// HISTORY. Adding a late participant may change the FUTURE -- new fixtures
// against the newcomer -- but must NEVER touch an existing match, played or
// not. This planner only ever ADDS brand-new fixtures in brand-new round
// numbers; it never edits or deletes anything in `existingMatches`.
//
// Format support: only LeagueFormat.classic (single round-robin table) has
// a safe, well-defined answer for "how do I insert one more team." The
// other formats all have an invariant a late joiner would break:
//   - uclGroup / worldCup: groups are a fixed size (exactly 4 teams each,
//     enforced by StandingsCalculator and the group->knockout seeding
//     functions) -- there is no "5th team in a group of 4."
//   - uclSwiss: the pairing engine requires an exact 18 or 36 team field
//     and a fixed round count; a team joining after round 1 cannot be
//     fairly seeded into the standings-based pairing it already ran.
//   - directKnockout: bracket sizes are a fixed power-of-two set
//     (4/8/16/32/64); inserting a team means reshaping the whole tree,
//     which risks exactly the "rewrite the past" this engagement exists
//     to prevent.
// Rather than forcing one algorithm onto every format, this planner reports
// the limitation up front via [LateJoinPlanner.supportsFormat] so the UI
// can explain it instead of attempting an unsafe restructure.

import '../domain/algorithms/round_robin.dart';
import '../models/enums.dart';
import '../models/fixture_match.dart';
import '../models/league_format.dart';

class LateJoinUnsupportedFormatException implements Exception {
  final LeagueFormat format;
  const LateJoinUnsupportedFormatException(this.format);

  String get message =>
      'Late joining is not supported for this league\'s format '
      '(${format.displayName}) yet. It is currently only available for '
      'Classic League (single round-robin table), since every other format '
      'has a fixed structure (group size, Swiss field size, or bracket '
      'size) that a new participant would break.';

  @override
  String toString() => message;
}

class LateJoinTeamAlreadyInLeagueException implements Exception {
  const LateJoinTeamAlreadyInLeagueException();

  String get message => 'This team is already part of the league.';

  @override
  String toString() => message;
}

/// What a late-join operation would do, computed before anything is
/// written -- the organizer-facing preview.
class LateJoinPreview {
  /// Existing matches that already have a saved result. Never touched.
  final int completedMatchCount;

  /// Existing matches not yet played. Never touched either -- counted
  /// separately only so the organizer can see the league's current state.
  final int futureMatchCount;

  /// Brand-new fixtures this operation would create (the newcomer vs every
  /// existing team, once for a single round-robin or twice for a double
  /// round-robin).
  final List<FixtureMatch> newFixtures;

  /// Always 0 for a supported format -- no existing match is ever edited
  /// or deleted by a late join. Kept as an explicit field (rather than a
  /// hardcoded assumption in the UI) so a future format addition can't
  /// silently violate it without the preview surfacing a nonzero count.
  final int existingMatchesAffectedCount;

  const LateJoinPreview({
    required this.completedMatchCount,
    required this.futureMatchCount,
    required this.newFixtures,
    this.existingMatchesAffectedCount = 0,
  });

  int get newFixtureCount => newFixtures.length;
}

class LateJoinPlanner {
  const LateJoinPlanner._();

  static bool supportsFormat(LeagueFormat format) =>
      format == LeagueFormat.classic;

  /// Plans (but does not write) adding [newTeamId] to a Classic League.
  ///
  /// Throws [LateJoinUnsupportedFormatException] if [format] isn't
  /// supported, or [LateJoinTeamAlreadyInLeagueException] if [newTeamId]
  /// is already one of [existingTeamIds].
  ///
  /// New fixtures are appended in brand-new round numbers after the
  /// highest existing round -- never interleaved into an existing round's
  /// pairing structure, so no existing fixture's round assignment changes.
  /// Home/away alternates across the newcomer's own fixtures so they are
  /// not always on one side.
  static LateJoinPreview preview({
    required LeagueFormat format,
    required String leagueId,
    required List<FixtureMatch> existingMatches,
    required List<String> existingTeamIds,
    required String newTeamId,
    required bool doubleRoundRobin,
  }) {
    if (!supportsFormat(format)) {
      throw LateJoinUnsupportedFormatException(format);
    }

    final trimmedNewId = newTeamId.trim();
    if (existingTeamIds.any((id) => id.trim() == trimmedNewId)) {
      throw const LateJoinTeamAlreadyInLeagueException();
    }

    final completedCount = existingMatches.where((m) => m.isPlayed).length;
    final futureCount = existingMatches.length - completedCount;

    var maxRound = 0;
    for (final m in existingMatches) {
      if (m.roundNumber > maxRound) maxRound = m.roundNumber;
    }

    final opponents = [...existingTeamIds]..sort();
    final now = DateTime.now().millisecondsSinceEpoch;

    final newFixtures = <FixtureMatch>[];
    var round = maxRound;
    for (var i = 0; i < opponents.length; i++) {
      final opponent = opponents[i];
      round += 1;

      final newcomerHome = i.isEven;
      final homeId = newcomerHome ? trimmedNewId : opponent;
      final awayId = newcomerHome ? opponent : trimmedNewId;

      newFixtures.add(FixtureMatch(
        id: RoundRobinGenerator.matchId(
          leagueId: leagueId,
          roundNumber: round,
          homeTeamId: homeId,
          awayTeamId: awayId,
        ),
        leagueId: leagueId,
        roundNumber: round,
        homeTeamId: homeId,
        awayTeamId: awayId,
        status: MatchStatus.scheduled,
        sortIndex: 0,
        updatedAtMs: now,
        version: 1,
      ));

      if (doubleRoundRobin) {
        round += 1;
        newFixtures.add(FixtureMatch(
          id: RoundRobinGenerator.matchId(
            leagueId: leagueId,
            roundNumber: round,
            homeTeamId: awayId,
            awayTeamId: homeId,
          ),
          leagueId: leagueId,
          roundNumber: round,
          homeTeamId: awayId,
          awayTeamId: homeId,
          status: MatchStatus.scheduled,
          sortIndex: 0,
          updatedAtMs: now,
          version: 1,
        ));
      }
    }

    return LateJoinPreview(
      completedMatchCount: completedCount,
      futureMatchCount: futureCount,
      newFixtures: newFixtures,
    );
  }
}
