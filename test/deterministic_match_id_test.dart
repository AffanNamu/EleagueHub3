// test/deterministic_match_id_test.dart
//
// PHASE C regression coverage: fixture generation must produce the same
// match document id for the same (league, group, round, home, away)
// every time it runs, so a retried write or a re-run generation (after
// FixtureRegenerationPlanner's "nothing played yet" check passes)
// converges onto the same Firestore documents instead of creating a
// second, independent set. Covers both engines that previously minted a
// fresh random uuid per call: RoundRobinGenerator (Classic/UCL-Group/
// World Cup) and SwissPairingEngine.

import 'package:eleaguehub3/features/leagues/domain/algorithms/round_robin.dart';
import 'package:eleaguehub3/features/leagues/domain/algorithms/swiss_pairing.dart';
import 'package:eleaguehub3/features/leagues/models/team.dart';
import 'package:flutter_test/flutter_test.dart';

Team _team(String id) => Team(
      id: id,
      leagueId: 'league1',
      name: id,
      updatedAtMs: 0,
      version: 1,
    );

void main() {
  group('RoundRobinGenerator.generate -- deterministic ids', () {
    test('regenerating with the same inputs produces identical ids', () {
      final first = RoundRobinGenerator.generate(
        leagueId: 'league1',
        teamIds: ['A', 'B', 'C', 'D'],
        doubleRoundRobin: false,
        startRoundNumber: 1,
      );
      final second = RoundRobinGenerator.generate(
        leagueId: 'league1',
        teamIds: ['A', 'B', 'C', 'D'],
        doubleRoundRobin: false,
        startRoundNumber: 1,
      );

      expect(first.map((m) => m.id).toList(), second.map((m) => m.id).toList());
    });

    test('every match in a single-leg schedule has a unique id', () {
      final matches = RoundRobinGenerator.generate(
        leagueId: 'league1',
        teamIds: ['A', 'B', 'C', 'D', 'E', 'F'],
        doubleRoundRobin: false,
        startRoundNumber: 1,
      );

      expect(matches.map((m) => m.id).toSet().length, matches.length);
    });

    test('double round-robin: leg 2 ids never collide with leg 1 ids', () {
      final matches = RoundRobinGenerator.generate(
        leagueId: 'league1',
        teamIds: ['A', 'B', 'C', 'D'],
        doubleRoundRobin: true,
        startRoundNumber: 1,
      );

      expect(matches.map((m) => m.id).toSet().length, matches.length);

      final firstLegIds =
          matches.where((m) => m.roundNumber <= 3).map((m) => m.id).toSet();
      final secondLegIds =
          matches.where((m) => m.roundNumber > 3).map((m) => m.id).toSet();
      expect(firstLegIds.intersection(secondLegIds), isEmpty);
    });

    test('different groups with the same pairing/round do not collide', () {
      final groupA = RoundRobinGenerator.generate(
        leagueId: 'league1',
        teamIds: ['A', 'B'],
        doubleRoundRobin: false,
        groupId: 'Group A',
        startRoundNumber: 1,
      );
      final groupB = RoundRobinGenerator.generate(
        leagueId: 'league1',
        teamIds: ['A', 'B'],
        doubleRoundRobin: false,
        groupId: 'Group B',
        startRoundNumber: 1,
      );

      expect(groupA.single.id, isNot(equals(groupB.single.id)));
    });

    test('different leagues never collide even with identical team ids/round', () {
      final league1 = RoundRobinGenerator.generate(
        leagueId: 'league1',
        teamIds: ['A', 'B'],
        doubleRoundRobin: false,
        startRoundNumber: 1,
      );
      final league2 = RoundRobinGenerator.generate(
        leagueId: 'league2',
        teamIds: ['A', 'B'],
        doubleRoundRobin: false,
        startRoundNumber: 1,
      );

      expect(league1.single.id, isNot(equals(league2.single.id)));
    });
  });

  group('SwissPairingEngine -- deterministic ids', () {
    test('generateInitialRound: same inputs produce identical ids', () {
      final teams = List.generate(18, (i) => _team('t$i'));
      final first = SwissPairingEngine.generateInitialRound(
        leagueId: 'league1',
        teams: teams,
        roundNumber: 1,
      );
      final second = SwissPairingEngine.generateInitialRound(
        leagueId: 'league1',
        teams: teams,
        roundNumber: 1,
      );

      expect(first.map((m) => m.id).toList(), second.map((m) => m.id).toList());
      expect(first.map((m) => m.id).toSet().length, first.length);
    });

    test('generateNextRound: same inputs produce identical ids, distinct from round 1', () {
      final teams = List.generate(18, (i) => _team('t$i'));
      final round1 = SwissPairingEngine.generateInitialRound(
        leagueId: 'league1',
        teams: teams,
        roundNumber: 1,
      );

      final round2First = SwissPairingEngine.generateNextRound(
        leagueId: 'league1',
        teams: teams,
        existingMatches: round1,
        nextRoundNumber: 2,
      );
      final round2Second = SwissPairingEngine.generateNextRound(
        leagueId: 'league1',
        teams: teams,
        existingMatches: round1,
        nextRoundNumber: 2,
      );

      expect(
        round2First.map((m) => m.id).toList(),
        round2Second.map((m) => m.id).toList(),
      );

      final round1Ids = round1.map((m) => m.id).toSet();
      final round2Ids = round2First.map((m) => m.id).toSet();
      expect(round1Ids.intersection(round2Ids), isEmpty);
    });
  });
}
