// lib/features/leagues/logic/replace_participant_planner.dart
//
// Safe participant replacement. Pure, Firestore-free decision logic --
// LocalLeaguesRepository.previewReplaceParticipant()/commitReplaceParticipant()
// are the only callers: they fetch the current league state, ask this
// planner what the operation would look like, and then only ever write
// exactly what the plan says.
//
// Core rule (same one as every earlier phase): a running competition has
// HISTORY. Replacing an inactive participant may change the FUTURE -- the
// REMAINING, unplayed/unfinished fixtures the old team was due to play --
// but must NEVER touch a completed match. This planner only ever updates
// the home/away team-id FIELD of an existing, unplayed/unfinished match
// document; it never changes the document's id, round/position, or any
// other field, and it never deletes or recreates anything.
//
// Format coverage: unlike late-join (Classic League only), replacement
// works for every format, because the operation itself is uniform --
// "find this team's not-yet-decided matches and relabel them" -- and the
// one thing that makes late-join unsafe for Group/Swiss/Knockout (an
// extra team breaking a fixed structure) does not apply here: the
// replacement team slots into an EXISTING position, so the structure
// (group size, Swiss field size, bracket shape) never changes.
//
// Eligibility gate (applies uniformly, and is what makes every
// format-specific worry in the brief a non-issue):
//   The replacement team must have ZERO existing appearances anywhere in
//   this competition (no FixtureMatch and no KnockoutMatch already
//   references it as home or away). This single rule:
//   - makes a Swiss "duplicate opponent" pairing structurally impossible
//     (the replacement has never played anyone here, so it can't repeat
//     an opponent),
//   - makes a knockout "merge two schedules" impossible (the replacement
//     isn't seeded anywhere else in the bracket),
//   - and for round-robin/group, guarantees the final schedule stays a
//     valid one-team-per-slot structure instead of double-booking a team
//     that already has its own fixtures.
//
// Two-legged ties (Swiss Play-off): if the sibling leg of an unfinished
// leg (same nextMatchId, opposite isSecondLeg) has ALREADY been decided,
// that leg is not eligible -- the aggregate/tiebreak logic in
// TournamentController.processMatchResult depends on both legs featuring
// the same two teams, and swapping one leg after the other is locked in
// would corrupt that comparison. The whole operation is rejected rather
// than applied partially.

import '../models/fixture_match.dart';
import '../models/knockout_match.dart';

class ReplaceParticipantBlockedException implements Exception {
  final String reason;
  const ReplaceParticipantBlockedException(this.reason);

  @override
  String toString() => reason;
}

/// What a replacement operation would do, computed before anything is
/// written -- the organizer-facing preview.
class ReplaceParticipantPreview {
  /// Matches already played/finished involving the old team. Never
  /// touched -- shown for context only.
  final int completedMatchCount;

  /// Fixture (non-knockout) matches to update: same id, same round/group,
  /// only the team-id field changes.
  final List<FixtureMatch> fixtureMatchesToUpdate;

  /// Knockout matches to update: same id, same bracket position
  /// (nextMatchId/loserGoesToMatchId untouched), only the team-id field
  /// changes.
  final List<KnockoutMatch> knockoutMatchesToUpdate;

  /// Always 0 -- no completed/finished match is ever included above.
  final int completedMatchesAffectedCount;

  const ReplaceParticipantPreview({
    required this.completedMatchCount,
    required this.fixtureMatchesToUpdate,
    required this.knockoutMatchesToUpdate,
    this.completedMatchesAffectedCount = 0,
  });

  int get eligibleMatchCount =>
      fixtureMatchesToUpdate.length + knockoutMatchesToUpdate.length;
}

class ReplaceParticipantPlanner {
  const ReplaceParticipantPlanner._();

  static bool _involves(FixtureMatch m, String teamId) =>
      m.homeTeamId == teamId || m.awayTeamId == teamId;

  static bool _involvesKo(KnockoutMatch m, String teamId) =>
      m.homeTeamId == teamId || m.awayTeamId == teamId;

  /// Plans replacing [oldTeamId] with [newTeamId] across every existing
  /// fixture/knockout match in the competition.
  ///
  /// Throws [ReplaceParticipantBlockedException] if:
  /// - [newTeamId] already appears anywhere in [existingFixtureMatches] or
  ///   [existingKnockoutMatches] (it must be a team with no existing
  ///   appearances in this competition), or
  /// - [oldTeamId] and [newTeamId] are the same, or
  /// - an unfinished Play-off leg's sibling leg has already been decided
  ///   (see file-level comment).
  static ReplaceParticipantPreview plan({
    required String oldTeamId,
    required String newTeamId,
    required List<FixtureMatch> existingFixtureMatches,
    required List<KnockoutMatch> existingKnockoutMatches,
  }) {
    final oldId = oldTeamId.trim();
    final newId = newTeamId.trim();

    if (oldId == newId) {
      throw const ReplaceParticipantBlockedException(
        'The replacement must be a different team from the one being replaced.',
      );
    }

    final newAlreadyPlaying = existingFixtureMatches.any((m) => _involves(m, newId)) ||
        existingKnockoutMatches.any((m) => _involvesKo(m, newId));
    if (newAlreadyPlaying) {
      throw const ReplaceParticipantBlockedException(
        'The replacement team already has its own fixtures in this competition. '
        'Choose a team with no existing matches, or create a new one.',
      );
    }

    final completedFixtures =
        existingFixtureMatches.where((m) => _involves(m, oldId) && m.isPlayed).length;
    final completedKnockouts = existingKnockoutMatches
        .where((m) => _involvesKo(m, oldId) && m.isFinished)
        .length;

    final eligibleFixtures = existingFixtureMatches
        .where((m) => _involves(m, oldId) && !m.isPlayed)
        .map((m) => m.homeTeamId == oldId
            ? m.copyWith(homeTeamId: newId)
            : m.copyWith(awayTeamId: newId))
        .toList();

    final eligibleKnockouts = <KnockoutMatch>[];
    for (final m in existingKnockoutMatches) {
      if (!_involvesKo(m, oldId) || m.isFinished) continue;

      if (m.roundName == 'Play-off' && m.nextMatchId != null) {
        final sibling = existingKnockoutMatches.where((other) =>
            other.roundName == 'Play-off' &&
            other.nextMatchId == m.nextMatchId &&
            other.isSecondLeg != m.isSecondLeg);
        if (sibling.any((s) => s.isFinished)) {
          throw ReplaceParticipantBlockedException(
            'Match ${m.id} is one leg of a two-legged Play-off tie whose other '
            'leg has already been played. Replacing a team mid-tie would break '
            'the aggregate result -- this replacement is rejected.',
          );
        }
      }

      eligibleKnockouts.add(m.homeTeamId == oldId
          ? m.copyWith(homeTeamId: newId)
          : m.copyWith(awayTeamId: newId));
    }

    return ReplaceParticipantPreview(
      completedMatchCount: completedFixtures + completedKnockouts,
      fixtureMatchesToUpdate: eligibleFixtures,
      knockoutMatchesToUpdate: eligibleKnockouts,
    );
  }
}
