// test/deterministic_knockout_id_test.dart
//
// PHASE C.1 priority 2: TournamentController's bracket-seeding functions
// used to embed DateTime.now().millisecondsSinceEpoch in every match id,
// so two concurrent/retried "generate bracket" calls (racing past the
// app-level "a bracket already exists" guard) minted two different ids
// for logically-identical matches -- a duplicate bracket. Match identity
// within one generation call is already fully determined by
// (leagueId, idPrefix, round short-code, 1-based index), so the fix drops
// the timestamp and keeps everything else -- including the trailing
// `_<index>` suffix _seedIndexFromId depends on for home/away slot
// assignment during advancement. See tournament_controller.dart's own
// comment on _buildKnockoutTree's id() closure.

import 'package:eleaguehub3/features/leagues/domain/logic/tournament_controller.dart';
import 'package:eleaguehub3/features/leagues/domain/standings/standings.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

StandingsRow _row(String teamId, {int w = 0, int d = 0, int l = 0, int gf = 0, int ga = 0}) {
  return StandingsRow(
    teamId: teamId,
    teamName: teamId,
    mp: w + d + l,
    w: w,
    d: d,
    l: l,
    gf: gf,
    ga: ga,
  );
}

void main() {
  group('TournamentController.seedTopNKnockouts -- deterministic ids', () {
    test('repeated generation with the same input produces identical ids', () {
      final teams = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
      final first = TournamentController.seedTopNKnockouts(
        leagueId: 'league1',
        rankedTeamIds: teams,
      );
      final second = TournamentController.seedTopNKnockouts(
        leagueId: 'league1',
        rankedTeamIds: teams,
      );

      expect(first.map((m) => m.id).toList(), second.map((m) => m.id).toList());
    });

    test('every match in one generation has a unique id (distinct bracket positions)', () {
      final teams = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
      final bracket = TournamentController.seedTopNKnockouts(
        leagueId: 'league1',
        rankedTeamIds: teams,
      );

      final ids = bracket.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('different leagues never collide even with an identical bracket shape', () {
      final teams = ['A', 'B', 'C', 'D'];
      final league1 = TournamentController.seedTopNKnockouts(
        leagueId: 'league1',
        rankedTeamIds: teams,
      );
      final league2 = TournamentController.seedTopNKnockouts(
        leagueId: 'league2',
        rankedTeamIds: teams,
      );

      final overlap = league1.map((m) => m.id).toSet().intersection(
            league2.map((m) => m.id).toSet(),
          );
      expect(overlap, isEmpty);
    });

    test('ids no longer embed a timestamp', () {
      final bracket = TournamentController.seedTopNKnockouts(
        leagueId: 'league1',
        rankedTeamIds: ['A', 'B', 'C', 'D'],
      );
      // Format is now `league1-TOPN-<ROUND>_<index>` -- exactly 3 hyphens
      // (leagueId-TOPN-ROUND, then _index), never a long millis-since-epoch
      // digit run.
      for (final m in bracket) {
        expect(m.id, startsWith('league1-TOPN-'));
        expect(RegExp(r'-\d{10,}_').hasMatch(m.id), isFalse,
            reason: 'id ${m.id} still looks like it embeds a timestamp');
      }
    });

    test('legitimate bracket advancement still works (winner fills the correct next-round slot)', () {
      final bracket = TournamentController.seedTopNKnockouts(
        leagueId: 'league1',
        rankedTeamIds: ['A', 'B', 'C', 'D'],
      );

      final semis = bracket.where((m) => m.roundName == 'Semi Finals').toList();
      expect(semis.length, 2);

      // A vs D (seed 1 vs seed 4) finishes 2-0 -> A advances.
      final semi1 = semis.firstWhere((m) => m.homeTeamId == 'A');
      final completedSemi1 = semi1.copyWith(
        homeScore: 2,
        awayScore: 0,
        status: MatchStatus.completed,
      );

      final afterSemi1 = TournamentController.processMatchResult(
        completedMatch: completedSemi1,
        allMatches: bracket.map((m) => m.id == semi1.id ? completedSemi1 : m).toList(),
      );

      final final_ = afterSemi1.firstWhere((m) => m.roundName == 'Final');
      expect(final_.homeTeamId == 'A' || final_.awayTeamId == 'A', isTrue);
    });
  });

  group('TournamentController.seedSwissKnockouts -- deterministic ids', () {
    List<StandingsRow> standings18() => [
          for (var i = 0; i < 18; i++) _row('t$i', w: 18 - i),
        ];

    test('repeated generation with the same input produces identical ids', () {
      final standings = standings18();
      final first = TournamentController.seedSwissKnockouts(
        leagueId: 'league1',
        swissStandings: standings,
      );
      final second = TournamentController.seedSwissKnockouts(
        leagueId: 'league1',
        swissStandings: standings,
      );

      expect(first.map((m) => m.id).toList(), second.map((m) => m.id).toList());
    });

    test('Play-off ids never collide with Quarter Finals ids', () {
      final bracket = TournamentController.seedSwissKnockouts(
        leagueId: 'league1',
        swissStandings: standings18(),
      );
      final ids = bracket.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('TournamentController.seedKnockoutsFromGroups -- deterministic ids', () {
    Map<String, List<StandingsRow>> groupsOf4() => {
          'Group A': [_row('A1', w: 3), _row('A2', w: 2), _row('A3', w: 1), _row('A4', w: 0)],
          'Group B': [_row('B1', w: 3), _row('B2', w: 2), _row('B3', w: 1), _row('B4', w: 0)],
          'Group C': [_row('C1', w: 3), _row('C2', w: 2), _row('C3', w: 1), _row('C4', w: 0)],
          'Group D': [_row('D1', w: 3), _row('D2', w: 2), _row('D3', w: 1), _row('D4', w: 0)],
        };

    test('repeated generation with the same group standings produces identical ids', () {
      final groups = groupsOf4();
      final first = TournamentController.seedKnockoutsFromGroups(
        leagueId: 'league1',
        groupStandings: groups,
      );
      final second = TournamentController.seedKnockoutsFromGroups(
        leagueId: 'league1',
        groupStandings: groups,
      );

      expect(first.map((m) => m.id).toList(), second.map((m) => m.id).toList());
    });
  });
}
