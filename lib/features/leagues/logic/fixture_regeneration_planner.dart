// lib/features/leagues/logic/fixture_regeneration_planner.dart
//
// Pure decision logic for regenerating (replacing) a league's round-robin
// -style match schedule -- deliberately kept free of any Firestore/IO
// dependency so the one rule that matters ("never silently destroy a
// played match") is unit-testable without a fake/live database.
//
// LocalLeaguesRepository.replaceMatches() is the only caller: it fetches
// the existing matches, asks this planner what to do, and then only ever
// executes exactly what the plan says.

import '../models/fixture_match.dart';

/// Thrown by [FixtureRegenerationPlanner.plan] when regeneration would
/// require touching a match that already has a saved result. Regeneration
/// is only ever safe before any match in the set has been played.
class FixtureRegenerationBlockedException implements Exception {
  final int playedMatchCount;
  const FixtureRegenerationBlockedException(this.playedMatchCount);

  String get message =>
      'Fixtures can\'t be regenerated: $playedMatchCount match'
      '${playedMatchCount == 1 ? '' : 'es'} already have a saved result. '
      'Regeneration is only available before any match in this competition '
      'has been played.';

  @override
  String toString() => message;
}

/// The result of planning a fixture regeneration: exactly which matches to
/// write (some reusing an existing document id) and which leftover existing
/// documents to delete.
class FixtureRegenerationPlan {
  /// Matches to upsert. Any pairing that already existed (same
  /// home/away/round) carries the OLD document id forward instead of the
  /// fresh id the generator assigned it, so the match's identity is
  /// preserved across a regeneration.
  final List<FixtureMatch> toWrite;

  /// Ids of existing documents that have no counterpart in the newly
  /// generated set (e.g. a team was removed, or the round structure
  /// changed) and should be deleted.
  final List<String> idsToDelete;

  const FixtureRegenerationPlan({
    required this.toWrite,
    required this.idsToDelete,
  });
}

class FixtureRegenerationPlanner {
  const FixtureRegenerationPlanner._();

  static String _pairKey(FixtureMatch m) =>
      '${m.homeTeamId}|${m.awayTeamId}|${m.roundNumber}';

  static FixtureMatch _withId(FixtureMatch m, String id) => FixtureMatch(
        id: id,
        leagueId: m.leagueId,
        groupId: m.groupId,
        roundNumber: m.roundNumber,
        homeTeamId: m.homeTeamId,
        awayTeamId: m.awayTeamId,
        homeScore: m.homeScore,
        awayScore: m.awayScore,
        status: m.status,
        sortIndex: m.sortIndex,
        updatedAtMs: m.updatedAtMs,
        version: m.version,
      );

  /// Plans a regeneration of [existing] into [generated].
  ///
  /// Throws [FixtureRegenerationBlockedException] if any match in
  /// [existing] already has a saved result (`FixtureMatch.isPlayed`) --
  /// a running competition's history is never silently replaced, no
  /// matter how the caller got here.
  static FixtureRegenerationPlan plan({
    required List<FixtureMatch> existing,
    required List<FixtureMatch> generated,
  }) {
    final playedCount = existing.where((m) => m.isPlayed).length;
    if (playedCount > 0) {
      throw FixtureRegenerationBlockedException(playedCount);
    }

    final existingByPairKey = <String, FixtureMatch>{};
    for (final m in existing) {
      existingByPairKey[_pairKey(m)] = m;
    }

    final usedExistingIds = <String>{};
    final toWrite = <FixtureMatch>[];
    for (final m in generated) {
      final match = existingByPairKey[_pairKey(m)];
      if (match != null) {
        usedExistingIds.add(match.id);
        toWrite.add(_withId(m, match.id));
      } else {
        toWrite.add(m);
      }
    }

    final idsToDelete = existing
        .where((m) => !usedExistingIds.contains(m.id))
        .map((m) => m.id)
        .toList(growable: false);

    return FixtureRegenerationPlan(toWrite: toWrite, idsToDelete: idsToDelete);
  }
}
