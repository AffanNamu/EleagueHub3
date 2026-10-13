// test/late_join_planner_test.dart
//
// PHASE D: regression coverage for LateJoinPlanner -- adding a participant
// to a running competition must only ever ADD new fixtures in brand-new
// round numbers, never touch an existing match (played or not), and must
// refuse outright for any format whose structure a late joiner would break.
// See lib/features/leagues/logic/late_join_planner.dart.

import 'package:eleaguehub3/features/leagues/logic/late_join_planner.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/fixture_match.dart';
import 'package:eleaguehub3/features/leagues/models/league_format.dart';
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
  group('LateJoinPlanner.supportsFormat', () {
    test('only Classic League is supported', () {
      expect(LateJoinPlanner.supportsFormat(LeagueFormat.classic), isTrue);
      expect(LateJoinPlanner.supportsFormat(LeagueFormat.uclGroup), isFalse);
      expect(LateJoinPlanner.supportsFormat(LeagueFormat.uclSwiss), isFalse);
      expect(LateJoinPlanner.supportsFormat(LeagueFormat.worldCup), isFalse);
      expect(LateJoinPlanner.supportsFormat(LeagueFormat.directKnockout), isFalse);
    });
  });

  group('LateJoinPlanner.preview -- unsupported formats', () {
    test('throws LateJoinUnsupportedFormatException for every non-classic format, naming the format', () {
      for (final format in [
        LeagueFormat.uclGroup,
        LeagueFormat.uclSwiss,
        LeagueFormat.worldCup,
        LeagueFormat.directKnockout,
      ]) {
        expect(
          () => LateJoinPlanner.preview(
            format: format,
            leagueId: 'league1',
            existingMatches: const [],
            existingTeamIds: const ['A', 'B'],
            newTeamId: 'NEW',
            doubleRoundRobin: false,
          ),
          throwsA(isA<LateJoinUnsupportedFormatException>()
              .having((e) => e.format, 'format', format)),
        );
      }
    });
  });

  group('LateJoinPlanner.preview -- Classic League', () {
    test('team already in the league is rejected', () {
      expect(
        () => LateJoinPlanner.preview(
          format: LeagueFormat.classic,
          leagueId: 'league1',
          existingMatches: const [],
          existingTeamIds: const ['A', 'B'],
          newTeamId: 'A',
          doubleRoundRobin: false,
        ),
        throwsA(isA<LateJoinTeamAlreadyInLeagueException>()),
      );
    });

    test('new fixtures are created against every existing team, single round-robin', () {
      final existing = [
        _match(id: 'm1', home: 'A', away: 'B', round: 1, status: MatchStatus.completed, homeScore: 1, awayScore: 0),
        _match(id: 'm2', home: 'A', away: 'C', round: 2),
      ];

      final preview = LateJoinPlanner.preview(
        format: LeagueFormat.classic,
        leagueId: 'league1',
        existingMatches: existing,
        existingTeamIds: const ['A', 'B', 'C'],
        newTeamId: 'NEW',
        doubleRoundRobin: false,
      );

      expect(preview.completedMatchCount, 1);
      expect(preview.futureMatchCount, 1);
      expect(preview.newFixtureCount, 3); // NEW vs A, NEW vs B, NEW vs C
      expect(preview.existingMatchesAffectedCount, 0);

      // Every new fixture involves the new team exactly once (home or away).
      for (final m in preview.newFixtures) {
        expect(m.homeTeamId == 'NEW' || m.awayTeamId == 'NEW', isTrue);
      }

      // No new fixture collides with an existing pairing/round.
      final existingIds = existing.map((m) => m.id).toSet();
      for (final m in preview.newFixtures) {
        expect(existingIds.contains(m.id), isFalse);
      }
    });

    test('double round-robin creates a home and an away fixture per existing team', () {
      final preview = LateJoinPlanner.preview(
        format: LeagueFormat.classic,
        leagueId: 'league1',
        existingMatches: const [],
        existingTeamIds: const ['A', 'B'],
        newTeamId: 'NEW',
        doubleRoundRobin: true,
      );

      expect(preview.newFixtureCount, 4); // NEW-A, A-NEW, NEW-B, B-NEW

      final aLegs = preview.newFixtures.where((m) => m.homeTeamId == 'A' || m.awayTeamId == 'A');
      expect(aLegs.length, 2);
      expect(aLegs.any((m) => m.homeTeamId == 'NEW' && m.awayTeamId == 'A'), isTrue);
      expect(aLegs.any((m) => m.homeTeamId == 'A' && m.awayTeamId == 'NEW'), isTrue);
    });

    test('new fixtures are placed in brand-new round numbers after the existing max round', () {
      final existing = [
        _match(id: 'm1', home: 'A', away: 'B', round: 5, status: MatchStatus.completed, homeScore: 2, awayScore: 2),
      ];

      final preview = LateJoinPlanner.preview(
        format: LeagueFormat.classic,
        leagueId: 'league1',
        existingMatches: existing,
        existingTeamIds: const ['A', 'B'],
        newTeamId: 'NEW',
        doubleRoundRobin: false,
      );

      for (final m in preview.newFixtures) {
        expect(m.roundNumber, greaterThan(5));
      }
    });

    test('no existing match (played or not) is ever included in the new-fixtures list', () {
      final existing = [
        _match(id: 'm1', home: 'A', away: 'B', round: 1, status: MatchStatus.completed, homeScore: 3, awayScore: 1),
        _match(id: 'm2', home: 'B', away: 'A', round: 2),
      ];

      final preview = LateJoinPlanner.preview(
        format: LeagueFormat.classic,
        leagueId: 'league1',
        existingMatches: existing,
        existingTeamIds: const ['A', 'B'],
        newTeamId: 'NEW',
        doubleRoundRobin: false,
      );

      final newIds = preview.newFixtures.map((m) => m.id).toSet();
      expect(newIds.contains('m1'), isFalse);
      expect(newIds.contains('m2'), isFalse);
      expect(preview.existingMatchesAffectedCount, 0);
    });

    test('new fixture ids use the same deterministic scheme as a regular generation run', () {
      final preview = LateJoinPlanner.preview(
        format: LeagueFormat.classic,
        leagueId: 'league1',
        existingMatches: const [],
        existingTeamIds: const ['A'],
        newTeamId: 'NEW',
        doubleRoundRobin: false,
      );

      final m = preview.newFixtures.single;
      expect(m.id, 'league1-RR-POOL-1-NEW-A');
    });

    test('planning twice in a row from the same unchanged state is stable (idempotent)', () {
      final existing = [
        _match(id: 'm1', home: 'A', away: 'B', round: 1, status: MatchStatus.completed, homeScore: 1, awayScore: 1),
      ];

      final first = LateJoinPlanner.preview(
        format: LeagueFormat.classic,
        leagueId: 'league1',
        existingMatches: existing,
        existingTeamIds: const ['A', 'B'],
        newTeamId: 'NEW',
        doubleRoundRobin: false,
      );
      final second = LateJoinPlanner.preview(
        format: LeagueFormat.classic,
        leagueId: 'league1',
        existingMatches: existing,
        existingTeamIds: const ['A', 'B'],
        newTeamId: 'NEW',
        doubleRoundRobin: false,
      );

      expect(
        first.newFixtures.map((m) => m.id).toList(),
        second.newFixtures.map((m) => m.id).toList(),
      );
    });
  });
}
