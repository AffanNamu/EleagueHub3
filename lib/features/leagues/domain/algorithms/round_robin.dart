import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../models/fixture_match.dart';
import '../../models/enums.dart';

/// The logic engine for generating league schedules.
class RoundRobinGenerator {
  static List<FixtureMatch> generate({
    required String leagueId,
    required List<String> teamIds,
    required bool doubleRoundRobin,
    String? groupId,
    required int startRoundNumber,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final uuid = const Uuid();

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
            id: uuid.v4(),
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
        id: uuid.v4(),
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
