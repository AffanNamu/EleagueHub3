// test/replace_participant_planner_test.dart
//
// Regression coverage for safe participant replacement: swapping an
// inactive team for an eligible one in a running competition must only
// ever touch unplayed/unfinished matches, never a completed one, and must
// refuse unsafe replacements (a replacement that already has its own
// fixtures, or a Play-off leg whose sibling is already decided).
// See lib/features/leagues/logic/replace_participant_planner.dart.

import 'package:eleaguehub3/features/leagues/logic/replace_participant_planner.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/fixture_match.dart';
import 'package:eleaguehub3/features/leagues/models/knockout_match.dart';
import 'package:flutter_test/flutter_test.dart';

FixtureMatch _fm({
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

KnockoutMatch _ko({
  required String id,
  required String roundName,
  String? home,
  String? away,
  MatchStatus status = MatchStatus.scheduled,
  int? homeScore,
  int? awayScore,
  String? nextMatchId,
  bool isSecondLeg = false,
}) {
  return KnockoutMatch(
    id: id,
    leagueId: 'league1',
    roundName: roundName,
    homeTeamId: home,
    awayTeamId: away,
    homeScore: homeScore,
    awayScore: awayScore,
    status: status,
    nextMatchId: nextMatchId,
    isSecondLeg: isSecondLeg,
  );
}

void main() {
  group('ReplaceParticipantPlanner.plan -- validation', () {
    test('replacement team must differ from the one being replaced', () {
      expect(
        () => ReplaceParticipantPlanner.plan(
          oldTeamId: 'A',
          newTeamId: 'A',
          existingFixtureMatches: const [],
          existingKnockoutMatches: const [],
        ),
        throwsA(isA<ReplaceParticipantBlockedException>()),
      );
    });

    test('replacement team already playing its own fixtures is rejected', () {
      final existing = [
        _fm(id: 'm1', home: 'A', away: 'B'),
        _fm(id: 'm2', home: 'NEW', away: 'C'),
      ];
      expect(
        () => ReplaceParticipantPlanner.plan(
          oldTeamId: 'A',
          newTeamId: 'NEW',
          existingFixtureMatches: existing,
          existingKnockoutMatches: const [],
        ),
        throwsA(isA<ReplaceParticipantBlockedException>()),
      );
    });

    test('replacement team already seeded in the knockout bracket is rejected', () {
      final koMatches = [
        _ko(id: 'k1', roundName: 'Quarter Finals', home: 'NEW', away: 'D'),
      ];
      expect(
        () => ReplaceParticipantPlanner.plan(
          oldTeamId: 'A',
          newTeamId: 'NEW',
          existingFixtureMatches: const [],
          existingKnockoutMatches: koMatches,
        ),
        throwsA(isA<ReplaceParticipantBlockedException>()),
      );
    });
  });

  group('ReplaceParticipantPlanner.plan -- round-robin / fixtures', () {
    test('replacement before any match has been played updates every fixture', () {
      final existing = [
        _fm(id: 'm1', home: 'A', away: 'B', round: 1),
        _fm(id: 'm2', home: 'C', away: 'A', round: 2),
      ];

      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: existing,
        existingKnockoutMatches: const [],
      );

      expect(preview.completedMatchCount, 0);
      expect(preview.fixtureMatchesToUpdate.length, 2);
      expect(preview.completedMatchesAffectedCount, 0);

      final m1 = preview.fixtureMatchesToUpdate.firstWhere((m) => m.id == 'm1');
      expect(m1.homeTeamId, 'NEW');
      expect(m1.awayTeamId, 'B');

      final m2 = preview.fixtureMatchesToUpdate.firstWhere((m) => m.id == 'm2');
      expect(m2.homeTeamId, 'C');
      expect(m2.awayTeamId, 'NEW');
    });

    test('completed matches are preserved exactly -- id, scores, status all untouched', () {
      final existing = [
        _fm(id: 'm1', home: 'A', away: 'B', round: 1, status: MatchStatus.completed, homeScore: 3, awayScore: 1),
        _fm(id: 'm2', home: 'A', away: 'C', round: 2),
      ];

      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: existing,
        existingKnockoutMatches: const [],
      );

      expect(preview.completedMatchCount, 1);
      expect(preview.fixtureMatchesToUpdate.length, 1);
      expect(preview.fixtureMatchesToUpdate.single.id, 'm2');

      // m1 never appears in the update list at all -- it is not touched.
      expect(preview.fixtureMatchesToUpdate.any((m) => m.id == 'm1'), isFalse);
    });

    test('unrelated fixtures (not involving the old team) are never included', () {
      final existing = [
        _fm(id: 'm1', home: 'A', away: 'B', round: 1),
        _fm(id: 'm2', home: 'C', away: 'D', round: 1),
      ];

      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: existing,
        existingKnockoutMatches: const [],
      );

      expect(preview.fixtureMatchesToUpdate.length, 1);
      expect(preview.fixtureMatchesToUpdate.single.id, 'm1');
    });

    test('match ids are always preserved -- never regenerated', () {
      final existing = [_fm(id: 'original-doc-id-123', home: 'A', away: 'B')];
      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: existing,
        existingKnockoutMatches: const [],
      );
      expect(preview.fixtureMatchesToUpdate.single.id, 'original-doc-id-123');
    });

    test('planning twice in a row from the same unchanged state is stable (retry-safe)', () {
      final existing = [_fm(id: 'm1', home: 'A', away: 'B')];
      final first = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: existing,
        existingKnockoutMatches: const [],
      );
      final second = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: existing,
        existingKnockoutMatches: const [],
      );
      expect(first.fixtureMatchesToUpdate.single.id, second.fixtureMatchesToUpdate.single.id);
      expect(first.fixtureMatchesToUpdate.single.homeTeamId, second.fixtureMatchesToUpdate.single.homeTeamId);
    });
  });

  group('ReplaceParticipantPlanner.plan -- knockout', () {
    test('an unfinished knockout match is updated, bracket wiring untouched', () {
      final koMatches = [
        _ko(id: 'qf1', roundName: 'Quarter Finals', home: 'A', away: 'D', nextMatchId: 'sf1'),
      ];

      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: const [],
        existingKnockoutMatches: koMatches,
      );

      final updated = preview.knockoutMatchesToUpdate.single;
      expect(updated.id, 'qf1');
      expect(updated.homeTeamId, 'NEW');
      expect(updated.awayTeamId, 'D');
      expect(updated.nextMatchId, 'sf1'); // bracket structure untouched
    });

    test('a finished knockout match and its winner are never altered', () {
      final koMatches = [
        _ko(
          id: 'qf1',
          roundName: 'Quarter Finals',
          home: 'A',
          away: 'D',
          status: MatchStatus.completed,
          homeScore: 2,
          awayScore: 0,
        ),
      ];

      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: const [],
        existingKnockoutMatches: koMatches,
      );

      expect(preview.completedMatchCount, 1);
      expect(preview.knockoutMatchesToUpdate, isEmpty);
    });

    test('a Play-off leg whose sibling leg is already decided is rejected', () {
      final koMatches = [
        _ko(
          id: 'po-leg1',
          roundName: 'Play-off',
          home: 'A',
          away: 'B',
          status: MatchStatus.completed,
          homeScore: 2,
          awayScore: 1,
          nextMatchId: 'r16-1',
          isSecondLeg: false,
        ),
        _ko(
          id: 'po-leg2',
          roundName: 'Play-off',
          home: 'B',
          away: 'A',
          nextMatchId: 'r16-1',
          isSecondLeg: true,
        ),
      ];

      expect(
        () => ReplaceParticipantPlanner.plan(
          oldTeamId: 'A',
          newTeamId: 'NEW',
          existingFixtureMatches: const [],
          existingKnockoutMatches: koMatches,
        ),
        throwsA(isA<ReplaceParticipantBlockedException>()),
      );
    });

    test('a Play-off leg whose sibling leg is also unplayed is allowed', () {
      final koMatches = [
        _ko(id: 'po-leg1', roundName: 'Play-off', home: 'A', away: 'B', nextMatchId: 'r16-1', isSecondLeg: false),
        _ko(id: 'po-leg2', roundName: 'Play-off', home: 'B', away: 'A', nextMatchId: 'r16-1', isSecondLeg: true),
      ];

      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: const [],
        existingKnockoutMatches: koMatches,
      );

      // Only the leg involving A (po-leg1) is updated; po-leg2 involves B
      // and the away slot of po-leg1's sibling, not A, so it's untouched
      // by this specific replacement unless it separately references A.
      expect(preview.knockoutMatchesToUpdate.any((m) => m.id == 'po-leg1'), isTrue);
    });
  });

  group('ReplaceParticipantPlanner.plan -- mixed format (group stage + knockout)', () {
    test('replacement updates both fixture and knockout matches in one plan', () {
      final fixtures = [_fm(id: 'g1', home: 'A', away: 'B', round: 1)];
      final koMatches = [_ko(id: 'qf1', roundName: 'Quarter Finals', home: 'A', away: 'D')];

      final preview = ReplaceParticipantPlanner.plan(
        oldTeamId: 'A',
        newTeamId: 'NEW',
        existingFixtureMatches: fixtures,
        existingKnockoutMatches: koMatches,
      );

      expect(preview.eligibleMatchCount, 2);
      expect(preview.fixtureMatchesToUpdate.single.id, 'g1');
      expect(preview.knockoutMatchesToUpdate.single.id, 'qf1');
    });
  });
}
