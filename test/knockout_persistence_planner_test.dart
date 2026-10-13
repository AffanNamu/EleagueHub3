// test/knockout_persistence_planner_test.dart
//
// PHASE C regression coverage for the fix to
// LocalLeaguesRepository.saveKnockoutMatches: it used to delete every
// existing knockout document before writing the passed-in list back,
// which meant every score submission (round-tripping the whole bracket,
// already-finished matches included) briefly deleted finished matches
// before recreating them -- both a standalone data-loss risk and,
// combined with firestore.rules' new knockoutMatchWriteRespectsHistory
// (which refuses to delete a finished match), a hard break of the
// advancement flow. See knockout_persistence_planner.dart.

import 'package:eleaguehub3/features/leagues/logic/knockout_persistence_planner.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/knockout_match.dart';
import 'package:flutter_test/flutter_test.dart';

KnockoutMatch _match({
  required String id,
  MatchStatus status = MatchStatus.scheduled,
  int? homeScore,
  int? awayScore,
}) {
  return KnockoutMatch(
    id: id,
    leagueId: 'league1',
    roundName: 'Semi Finals',
    homeTeamId: 'A',
    awayTeamId: 'B',
    homeScore: homeScore,
    awayScore: awayScore,
    status: status,
  );
}

void main() {
  group('KnockoutPersistencePlanner.idsToPrune', () {
    test('finished matches round-tripping through the save (same ids) are never pruned', () {
      final finished = _match(
        id: 'm1',
        status: MatchStatus.completed,
        homeScore: 2,
        awayScore: 1,
      );
      final idsToPrune = KnockoutPersistencePlanner.idsToPrune(
        existing: [finished],
        matches: [finished],
      );

      expect(idsToPrune, isEmpty);
    });

    test('unfinished matches no longer part of the bracket ARE pruned', () {
      final existing = [
        _match(id: 'm1', status: MatchStatus.scheduled),
        _match(id: 'm2', status: MatchStatus.scheduled),
      ];
      // Bracket rebuild: only m1 survives.
      final idsToPrune = KnockoutPersistencePlanner.idsToPrune(
        existing: existing,
        matches: [existing[0]],
      );

      expect(idsToPrune, ['m2']);
    });

    test('a FINISHED match with no counterpart in the new list is never pruned (history protected)', () {
      final existing = [
        _match(
          id: 'finished-but-dropped',
          status: MatchStatus.completed,
          homeScore: 3,
          awayScore: 0,
        ),
      ];
      final idsToPrune = KnockoutPersistencePlanner.idsToPrune(
        existing: existing,
        matches: const [],
      );

      expect(idsToPrune, isEmpty);
    });

    test('a status alone (no scores) is NOT treated as finished -- matches KnockoutMatch.isFinished', () {
      final existing = [
        _match(id: 'm1', status: MatchStatus.played), // no scores
      ];
      final idsToPrune = KnockoutPersistencePlanner.idsToPrune(
        existing: existing,
        matches: const [],
      );

      expect(idsToPrune, ['m1']);
    });

    test('mixed bracket: finished matches kept, unfinished+dropped match pruned', () {
      final finished = _match(
        id: 'sf1',
        status: MatchStatus.completed,
        homeScore: 1,
        awayScore: 0,
      );
      final stillPending = _match(id: 'sf2', status: MatchStatus.scheduled);
      final droppedPending = _match(id: 'stale', status: MatchStatus.scheduled);

      final idsToPrune = KnockoutPersistencePlanner.idsToPrune(
        existing: [finished, stillPending, droppedPending],
        matches: [finished, stillPending],
      );

      expect(idsToPrune, ['stale']);
    });
  });
}
