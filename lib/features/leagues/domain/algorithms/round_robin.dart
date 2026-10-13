
///league/domain/algorithms.
import 'package:collection/collection.dart';

import '../../models/fixture_match.dart';
import '../../models/enums.dart';

/// The logic engine for generating league schedules.
class RoundRobinGenerator {
  /// Deterministic match id from (league, group, round, home, away) --
  /// PHASE C: random UUIDs meant a retried or re-run generation produced a
  /// second, independent set of match documents instead of converging on
  /// the same ones. A deterministic id makes every write for the exact
  /// same pairing/round land on the exact same Firestore document, so
  /// FixtureRegenerationPlanner's id-reuse matching (Phase A) and a
  /// network retry both naturally dedupe at the document-id level, not
  /// just via business-logic matching.
  ///
  /// PHASE D: made public so LateJoinPlanner can mint ids for a late
  /// joiner's new fixtures using the exact same formula a regular
  /// generation run would -- a late-join fixture is indistinguishable
  /// from one produced by a normal generate() call.
  static String matchId({
    required String leagueId,
    String? groupId,
    required int roundNumber,
    required String homeTeamId,
    required String awayTeamId,
  }) {
    final g = (groupId ?? '').trim();
    return '$leagueId-RR-${g.isEmpty ? 'POOL' : g}-$roundNumber-$homeTeamId-$awayTeamId';
  }

  static List<FixtureMatch> generate({
    required String leagueId,
    required List<String> teamIds,
    required bool doubleRoundRobin,
    String? groupId,
    required int startRoundNumber,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    final ids = [...teamIds];
    ids.sort();

    String? bye;
    if (ids.length.isOdd) {
      bye = '__BYE__';
      ids.add(bye);
    }

    final n = ids.length;
    if (n < 2) return [];

    var rotation = [...ids];
    final rounds = n - 1;
    final fixtures = <FixtureMatch>[];

    for (var r = 0; r < rounds; r++) {
      final pairs = <(String, String)>{};
      for (var i = 0; i < n ~/ 2; i++) {
        final a = rotation[i];
        final b = rotation[n - 1 - i];
        if (a == bye || b == bye) continue;
        pairs.add((a, b));
      }

      final swapRound = r.isOdd;
      final roundPairsList = pairs.toList();
      for (var i = 0; i < roundPairsList.length; i++) {
        final (a, b) = roundPairsList[i];
        final swapPair = i.isOdd;
        final swap = swapRound ^ swapPair;
        final home = swap ? b : a;
        final away = swap ? a : b;

        fixtures.add(
          FixtureMatch(
            id: matchId(
              leagueId: leagueId,
              groupId: groupId,
              roundNumber: startRoundNumber + r,
              homeTeamId: home,
              awayTeamId: away,
            ),
            leagueId: leagueId,
            groupId: groupId,
            roundNumber: startRoundNumber + r,
            homeTeamId: home,
            awayTeamId: away,
            homeScore: null,
            awayScore: null,
            status: MatchStatus.scheduled,
            sortIndex: i,
            updatedAtMs: now,
            version: 1,
          ),
        );
      }
      rotation = _rotate(rotation);
    }

    if (!doubleRoundRobin) return fixtures;

    final secondLeg = fixtures.mapIndexed((idx, m) {
      return FixtureMatch(
        id: matchId(
          leagueId: leagueId,
          groupId: groupId,
          roundNumber: m.roundNumber + rounds,
          homeTeamId: m.awayTeamId,
          awayTeamId: m.homeTeamId,
        ),
        leagueId: leagueId,
        groupId: groupId,
        roundNumber: m.roundNumber + rounds,
        homeTeamId: m.awayTeamId,
        awayTeamId: m.homeTeamId,
        homeScore: null,
        awayScore: null,
        status: MatchStatus.scheduled,
        sortIndex: m.sortIndex,
        updatedAtMs: now,
        version: 1,
      );
    }).toList();

    return [...fixtures, ...secondLeg];
  }

  static List<String> _rotate(List<String> list) {
    if (list.length < 2) return list;
    final result = List<String>.from(list);
    final last = result.removeLast();
    result.insert(1, last);
    return result;
  }
}
