// test/fixture_regeneration_planner_test.dart
//
// Regression coverage for the production-safety fix to
// LocalLeaguesRepository.replaceMatches(): regenerating a league's
// schedule must never silently delete a match that already has a saved
// result. See lib/features/leagues/logic/fixture_regeneration_planner.dart.

import 'package:eleaguehub3/features/leagues/logic/fixture_regeneration_planner.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/fixture_match.dart';
import 'package:flutter_test/flutter_test.dart';

FixtureMatch _match({
  required String id,
  required String home,
  required String away,
  int round = 1,
  MatchStatus status = MatchStatus.scheduled,
  int? homeScore,
  int? awayScore,
}) {
  return FixtureMatch(
    id: id,
    leagueId: 'league1',
    roundNumber: round,
    homeTeamId: home,
    awayTeamId: away,
    homeScore: homeScore,
    awayScore: awayScore,
    status: status,
    sortIndex: 0,
    updatedAtMs: 0,
    version: 1,
  );
}

void main() {
  group('FixtureRegenerationPlanner.plan', () {
    test('fresh league with no existing matches: generates everything as-is', () {
      final generated = [
        _match(id: 'gen-1', home: 'A', away: 'B'),
        _match(id: 'gen-2', home: 'C', away: 'D'),
      ];

      final plan = FixtureRegenerationPlanner.plan(
        existing: const [],
        generated: generated,
      );

      expect(plan.idsToDelete, isEmpty);
      expect(plan.toWrite.map((m) => m.id), ['gen-1', 'gen-2']);
    });

    test(
        'no matches played yet: regeneration is allowed and unchanged pairings keep their old id',
        () {
      final existing = [
        _match(id: 'old-1', home: 'A', away: 'B', round: 1),
        _match(id: 'old-2', home: 'C', away: 'D', round: 1),
      ];
      // Team D was removed and replaced with E -- same shape (2 teams,
      // round 1) but a different pairing for the second match.
      final generated = [
        _match(id: 'fresh-1', home: 'A', away: 'B', round: 1),
        _match(id: 'fresh-2', home: 'C', away: 'E', round: 1),
      ];

      final plan = FixtureRegenerationPlanner.plan(
        existing: existing,
        generated: generated,
      );

      // A-vs-B unchanged -> keeps its original doc id.
      final abMatch = plan.toWrite.firstWhere(
        (m) => m.homeTeamId == 'A' && m.awayTeamId == 'B',
      );
      expect(abMatch.id, 'old-1');

      // C-vs-E is a new pairing -> keeps the generator's fresh id.
      final ceMatch = plan.toWrite.firstWhere(
        (m) => m.homeTeamId == 'C' && m.awayTeamId == 'E',
      );
      expect(ceMatch.id, 'fresh-2');

      // C-vs-D no longer exists in the new set -> its old doc is deleted.
      expect(plan.idsToDelete, ['old-2']);
    });

    test(
        'any existing match already played: regeneration is blocked and nothing is planned for deletion',
        () {
      final existing = [
        _match(
          id: 'old-1',
          home: 'A',
          away: 'B',
          status: MatchStatus.completed,
          homeScore: 2,
          awayScore: 1,
        ),
        _match(id: 'old-2', home: 'C', away: 'D'),
      ];
      final generated = [
        _match(id: 'fresh-1', home: 'A', away: 'B'),
        _match(id: 'fresh-2', home: 'C', away: 'D'),
        _match(id: 'fresh-3', home: 'E', away: 'F'),
      ];

      expect(
        () => FixtureRegenerationPlanner.plan(
          existing: existing,
          generated: generated,
        ),
        throwsA(isA<FixtureRegenerationBlockedException>()),
      );
    });

    test('exception message reports the exact count of played matches', () {
      final existing = [
        _match(
          id: 'old-1',
          home: 'A',
          away: 'B',
          status: MatchStatus.completed,
          homeScore: 1,
          awayScore: 0,
        ),
        _match(
          id: 'old-2',
          home: 'C',
          away: 'D',
          status: MatchStatus.played,
          homeScore: 3,
          awayScore: 3,
        ),
        _match(id: 'old-3', home: 'E', away: 'F'),
      ];

      try {
        FixtureRegenerationPlanner.plan(existing: existing, generated: const []);
        fail('expected FixtureRegenerationBlockedException');
      } on FixtureRegenerationBlockedException catch (e) {
        expect(e.playedMatchCount, 2);
        expect(e.message, contains('2 matches'));
      }
    });

    test('a match with a status but no score is NOT treated as played', () {
      // Mirrors FixtureMatch.isPlayed's own contract: status alone isn't
      // enough, both scores must be present too.
      final existing = [
        _match(id: 'old-1', home: 'A', away: 'B', status: MatchStatus.played),
      ];
      final generated = [
        _match(id: 'fresh-1', home: 'A', away: 'B'),
      ];

      final plan = FixtureRegenerationPlanner.plan(
        existing: existing,
        generated: generated,
      );

      expect(plan.toWrite.single.id, 'old-1');
      expect(plan.idsToDelete, isEmpty);
    });

    test('generating twice in a row with identical pairings is stable (same ids, no deletes)', () {
      final existing = [
        _match(id: 'old-1', home: 'A', away: 'B', round: 1),
        _match(id: 'old-2', home: 'B', away: 'A', round: 2),
      ];
      final generated = [
        _match(id: 'fresh-1', home: 'A', away: 'B', round: 1),
        _match(id: 'fresh-2', home: 'B', away: 'A', round: 2),
      ];

      final plan = FixtureRegenerationPlanner.plan(
        existing: existing,
        generated: generated,
      );

      expect(plan.idsToDelete, isEmpty);
      expect(
        plan.toWrite.map((m) => m.id).toSet(),
        {'old-1', 'old-2'},
      );
    });

    test('home/away legs stay distinguishable (A-vs-B round 1 != B-vs-A round 2)', () {
      final existing = [
        _match(id: 'leg-1', home: 'A', away: 'B', round: 1),
        _match(id: 'leg-2', home: 'B', away: 'A', round: 2),
      ];
      final generated = [
        _match(id: 'gen-1', home: 'A', away: 'B', round: 1),
        _match(id: 'gen-2', home: 'B', away: 'A', round: 2),
      ];

      final plan = FixtureRegenerationPlanner.plan(
        existing: existing,
        generated: generated,
      );

      final firstLeg = plan.toWrite.firstWhere((m) => m.roundNumber == 1);
      final secondLeg = plan.toWrite.firstWhere((m) => m.roundNumber == 2);
      expect(firstLeg.id, 'leg-1');
      expect(secondLeg.id, 'leg-2');
      expect(firstLeg.homeTeamId, 'A');
      expect(secondLeg.homeTeamId, 'B');
    });
  });
}
