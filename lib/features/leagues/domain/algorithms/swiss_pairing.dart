import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../models/enums.dart';
import '../../models/fixture_match.dart';
import '../../models/team.dart';
import '../../models/team_stats.dart';

/// Swiss-pairing engine for league phase:
/// - Allowed team counts: 18 or 36 (no byes)
/// - Round 1: deterministic shuffle
/// - Later rounds: pair teams by ranking proximity, STRICTLY avoid rematches
///
/// CRITICAL INTEGRITY:
/// This implementation uses a backtracking perfect-matching builder (not greedy),
/// so it will not "get stuck" simply due to greedy choice when a valid pairing exists.
class SwissPairingEngine {
  static final _uuid = const Uuid();

  static int _fnv1a32(String input) {
    const int fnvOffsetBasis = 0x811c9dc5;
    const int fnvPrime = 0x01000193;

    var hash = fnvOffsetBasis;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  static int _stableSeed(String leagueId, int roundNumber) {
    return (_fnv1a32(leagueId) ^ roundNumber) & 0x7FFFFFFF;
  }

  static bool _allowedTeamCount(int n) => n == 18 || n == 36;

  static String _pairKey(String a, String b) {
    return (a.compareTo(b) < 0) ? '$a|$b' : '$b|$a';
  }

  static Map<String, int> _homeCounts({
    required List<Team> teams,
    required List<FixtureMatch> matches,
    required int beforeRound,
  }) {
    final counts = <String, int>{for (final t in teams) t.id: 0};
    for (final m in matches) {
      if (m.roundNumber >= beforeRound) continue;
      counts[m.homeTeamId] = (counts[m.homeTeamId] ?? 0) + 1;
    }
    return counts;
  }

  static Map<String, int> _awayCounts({
    required List<Team> teams,
    required List<FixtureMatch> matches,
    required int beforeRound,
  }) {
    final counts = <String, int>{for (final t in teams) t.id: 0};
    for (final m in matches) {
      if (m.roundNumber >= beforeRound) continue;
      counts[m.awayTeamId] = (counts[m.awayTeamId] ?? 0) + 1;
    }
    return counts;
  }

  /// Build a full non-rematch pairing using backtracking perfect matching.
  ///
  /// Input:
  /// - teamIds: the set of teams to pair this round (even size)
  /// - rankIndex: lower index = higher rank (used only to prefer closer pairings)
  /// - previousPairs: already played/generated pairs that must be avoided
  /// - homeCount/awayCount: prior schedule counts to keep home/away balanced
  ///
  /// Returns: list of (home, away) pairs or [] if no valid pairing exists.
  static List<({String home, String away})> _buildPairingBacktracking({
    required List<String> teamIds,
    required Map<String, int> rankIndex,
    required Set<String> previousPairs,
    required Map<String, int> homeCount,
    required Map<String, int> awayCount,
    required Random rand,
    required int totalRounds, // for 8 matches => maxHome=maxAway=4
  }) {
    final maxHome = (totalRounds / 2).floor();
    final maxAway = totalRounds - maxHome;

    // Deterministic tie-break weights for candidates
    final randWeight = <String, int>{
      for (final id in teamIds) id: rand.nextInt(1 << 30),
    };

    final unpaired = teamIds.toSet();
    final result = <({String home, String away})>[];

    int candidateCount(String a) {
      int c = 0;
      for (final b in unpaired) {
        if (b == a) continue;
        if (previousPairs.contains(_pairKey(a, b))) continue;
        c++;
      }
      return c;
    }

    List<String> candidatesFor(String a) {
      final aRank = rankIndex[a] ?? 999999;
      final list = <String>[];

      for (final b in unpaired) {
        if (b == a) continue;
        if (previousPairs.contains(_pairKey(a, b))) continue;
        list.add(b);
      }

      // Prefer close ranks (Swiss style) + deterministic random to break ties.
      list.sort((b1, b2) {
        final d1 = ((rankIndex[b1] ?? 999999) - aRank).abs();
        final d2 = ((rankIndex[b2] ?? 999999) - aRank).abs();
        if (d1 != d2) return d1.compareTo(d2);

        final c1 = candidateCount(b1);
        final c2 = candidateCount(b2);
        if (c1 != c2) return c1.compareTo(c2);

        return (randWeight[b1] ?? 0).compareTo(randWeight[b2] ?? 0);
      });

      return list;
    }

    bool canHome(String teamId) => (homeCount[teamId] ?? 0) < maxHome;
    bool canAway(String teamId) => (awayCount[teamId] ?? 0) < maxAway;

    bool mustAway(String teamId) => !canHome(teamId); // already at maxHome
    bool mustHome(String teamId) => !canAway(teamId); // already at maxAway

    List<({String home, String away})> orientations(String a, String b) {
      final out = <({String home, String away})>[];

      // Option 1: a home, b away
      if (!mustAway(a) && !mustHome(b) && canHome(a) && canAway(b)) {
        out.add((home: a, away: b));
      }

      // Option 2: b home, a away
      if (!mustAway(b) && !mustHome(a) && canHome(b) && canAway(a)) {
        out.add((home: b, away: a));
      }

      // Prefer giving home to the one with fewer home matches
      out.sort((x, y) {
        final hx = homeCount[x.home] ?? 0;
        final hy = homeCount[y.home] ?? 0;
        if (hx != hy) return hx.compareTo(hy);
        return (randWeight[x.home] ?? 0).compareTo(randWeight[y.home] ?? 0);
      });

      return out;
    }

    bool backtrack() {
      if (unpaired.isEmpty) return true;

      // Choose the most constrained team (fewest candidates) to reduce branching.
      String? a;
      int best = 1 << 30;
      for (final id in unpaired) {
        final c = candidateCount(id);
        if (c < best) {
          best = c;
          a = id;
          if (best == 0) break;
        }
      }

      if (a == null || best == 0) return false;

      final cand = candidatesFor(a);

      for (final b in cand) {
        if (!unpaired.contains(b)) continue;

        final key = _pairKey(a, b);
        if (previousPairs.contains(key)) continue;

        // Try possible home/away orientations under maxHome/maxAway constraints.
        final opts = orientations(a, b);
        if (opts.isEmpty) continue;

        // Apply pairing
        unpaired.remove(a);
        unpaired.remove(b);
        previousPairs.add(key);

        for (final opt in opts) {
          // apply orientation counts
          homeCount[opt.home] = (homeCount[opt.home] ?? 0) + 1;
          awayCount[opt.away] = (awayCount[opt.away] ?? 0) + 1;

          // Keep record type named (home/away)
          result.add(opt);

          if (backtrack()) return true;

          // rollback orientation
          result.removeLast();
          homeCount[opt.home] = (homeCount[opt.home] ?? 1) - 1;
          awayCount[opt.away] = (awayCount[opt.away] ?? 1) - 1;
        }

        // rollback pairing
        previousPairs.remove(key);
        unpaired.add(a);
        unpaired.add(b);
      }

      return false;
    }

    final ok = backtrack();
    return ok ? result : <({String home, String away})>[];
  }

  /// Generate Round 1 pairings (deterministic per league).
  static List<FixtureMatch> generateInitialRound({
    required String leagueId,
    required List<Team> teams,
    required int roundNumber,
    int totalRounds = 8, // your spec: 8 matches each
  }) {
    if (teams.length < 2) return [];
    if (!_allowedTeamCount(teams.length)) return [];
    if (teams.length.isOdd) return [];

    final rand = Random(_stableSeed(leagueId, roundNumber));
    final shuffled = List<Team>.from(teams)..shuffle(rand);

    final ids = shuffled.map((t) => t.id).toList();

    // Round 1 has no previous pairs and no prior home/away counts.
    final previousPairs = <String>{};
    final rankIndex = <String, int>{
      for (var i = 0; i < ids.length; i++) ids[i]: i,
    };

    final homeCount = <String, int>{for (final t in teams) t.id: 0};
    final awayCount = <String, int>{for (final t in teams) t.id: 0};

    final pairs = _buildPairingBacktracking(
      teamIds: ids,
      rankIndex: rankIndex,
      previousPairs: previousPairs,
      homeCount: homeCount,
      awayCount: awayCount,
      rand: rand,
      totalRounds: totalRounds,
    );

    if (pairs.isEmpty) return [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final fixtures = <FixtureMatch>[];
    for (var i = 0; i < pairs.length; i++) {
      fixtures.add(
        FixtureMatch(
          id: _uuid.v4(),
          leagueId: leagueId,
          groupId: null,
          roundNumber: roundNumber,
          homeTeamId: pairs[i].home,
          awayTeamId: pairs[i].away,
          homeScore: null,
          awayScore: null,
          status: MatchStatus.scheduled,
          sortIndex: i,
          updatedAtMs: now,
          version: 1,
        ),
      );
    }

    return fixtures;
  }

  /// Generate the next Swiss round pairings.
  ///
  /// - STRICT no-rematch enforcement across all rounds already generated.
  /// - Backtracking perfect matching prevents greedy dead-ends.
  /// - Uses played matches only to compute stats ordering, but uses all generated
  ///   matches (played or not) to block rematches.
  static List<FixtureMatch> generateNextRound({
    required String leagueId,
    required List<Team> teams,
    required List<FixtureMatch> existingMatches,
    required int nextRoundNumber,
    int totalRounds = 8,
  }) {
    if (teams.length < 2) return [];
    if (!_allowedTeamCount(teams.length)) return [];
    if (teams.length.isOdd) return [];

    final rand = Random(_stableSeed(leagueId, nextRoundNumber));
    final now = DateTime.now().millisecondsSinceEpoch;

    // Build set of previous pairs (rounds already generated before nextRoundNumber).
    final previousPairs = <String>{};
    for (final m in existingMatches.where((m) => m.roundNumber < nextRoundNumber)) {
      previousPairs.add(_pairKey(m.homeTeamId, m.awayTeamId));
    }

    // Consider only played matches before this round for ranking stats.
    final played = existingMatches.where((m) => m.isPlayed && m.roundNumber < nextRoundNumber).toList();

    // Build base stats for all teams.
    final stats = <String, TeamStats>{
      for (final t in teams) t.id: TeamStats.empty(teamId: t.id, leagueId: leagueId),
    };

    for (final m in played) {
      final hs = m.homeScore!;
      final as = m.awayScore!;
      stats[m.homeTeamId] = stats[m.homeTeamId]!.applyMatch(scored: hs, conceded: as);
      stats[m.awayTeamId] = stats[m.awayTeamId]!.applyMatch(scored: as, conceded: hs);
    }

    // Order teams by Swiss ranking tie-breakers.
    final ordered = stats.values.toList()
      ..sort((a, b) {
        final p = b.points.compareTo(a.points);
        if (p != 0) return p;
        final gd = b.goalDifference.compareTo(a.goalDifference);
        if (gd != 0) return gd;
        final gf = b.goalsFor.compareTo(a.goalsFor);
        if (gf != 0) return gf;
        return a.teamId.compareTo(b.teamId);
      });

    final orderedIds = ordered.map((s) => s.teamId).toList();

    // Rank index for "pair close ranks" preference in backtracking.
    final rankIndex = <String, int>{
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };

    // Home/away schedule balancing counts from already generated rounds.
    final homeCount = _homeCounts(teams: teams, matches: existingMatches, beforeRound: nextRoundNumber);
    final awayCount = _awayCounts(teams: teams, matches: existingMatches, beforeRound: nextRoundNumber);

    final pairs = _buildPairingBacktracking(
      teamIds: orderedIds,
      rankIndex: rankIndex,
      previousPairs: previousPairs,
      homeCount: homeCount,
      awayCount: awayCount,
      rand: rand,
      totalRounds: totalRounds,
    );

    if (pairs.isEmpty) return [];

    final fixtures = <FixtureMatch>[];
    for (var i = 0; i < pairs.length; i++) {
      fixtures.add(
        FixtureMatch(
          id: _uuid.v4(),
          leagueId: leagueId,
          groupId: null,
          roundNumber: nextRoundNumber,
          homeTeamId: pairs[i].home,
          awayTeamId: pairs[i].away,
          homeScore: null,
          awayScore: null,
          status: MatchStatus.scheduled,
          sortIndex: i,
          updatedAtMs: now,
          version: 1,
        ),
      );
    }

    return fixtures;
  }
}
