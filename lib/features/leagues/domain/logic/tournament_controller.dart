// lib/features/leagues/domain/logic/tournament_controller.dart
//
// MODIFIED: Added World Cup knockout engine.
//
// New public methods:
//   - seedWorldCupKnockouts32()  — FIFA 2022: 8 groups → R16 → QF → SF → 3P → Final
//   - seedWorldCupKnockouts48()  — FIFA 2026: 12 groups → R32 → R16 → QF → SF → 3P → Final
//   - _buildWorldCupBracket32()  — internal bracket builder for 32-team format
//   - _buildWorldCupBracket48()  — internal bracket builder for 48-team format
//   - WorldCupQualifiedTeam      — value object used for qualification seeding
//
// All existing methods (seedKnockoutsFromGroups, seedSwissKnockouts,
// processMatchResult, _buildKnockoutTree, etc.) are completely unchanged.

import 'dart:math';

import '../../models/enums.dart';
import '../../models/knockout_match.dart';
import '../standings/standings.dart';

/// Used internally to decide which slot (home/away) a feeder match writes into
/// in the next match. Must be top-level in Dart.
enum _KoSlot { home, away }

// ---------------------------------------------------------------------------
// WorldCupQualifiedTeam — value object used during seeding
// ---------------------------------------------------------------------------

/// Represents a team that has qualified from the World Cup group stage,
/// along with how they qualified (used for correct bracket seeding).
class WorldCupQualifiedTeam {
  /// Firebase team ID.
  final String teamId;

  /// The group this team came from (e.g., 'Group A').
  final String groupId;

  /// How this team qualified.
  final WorldCupQualificationSlot slot;

  /// Position within their slot category (1-based).
  /// Used for correct bracket seeding per FIFA rules.
  final int slotRank;

  const WorldCupQualifiedTeam({
    required this.teamId,
    required this.groupId,
    required this.slot,
    required this.slotRank,
  });
}

// ---------------------------------------------------------------------------
// TournamentController
// ---------------------------------------------------------------------------

class TournamentController {
  static String _shortCode(String roundName) {
    switch (roundName) {
      case 'Play-off':
        return 'PO';
      case 'Round of 32':
        return 'R32';
      case 'Round of 16':
        return 'R16';
      case 'Quarter Finals':
        return 'QF';
      case 'Semi Finals':
        return 'SF';
      case 'Final':
        return 'F';
      case '3rd Place':
        return '3P';
      default:
        return 'KO';
    }
  }

  static String _nextRoundName(String current) {
    switch (current) {
      case 'Round of 32':
        return 'Round of 16';
      case 'Round of 16':
        return 'Quarter Finals';
      case 'Quarter Finals':
        return 'Semi Finals';
      case 'Semi Finals':
        return 'Final';
      default:
        return '';
    }
  }

  /// Builds a KO tree skeleton from a specified start round.
  /// Wires nextMatchId from each match to the next round match.
  ///
  /// Now supports 'Round of 32' as a valid start round for FIFA 2026.
  static List<KnockoutMatch> _buildKnockoutTree({
    required String leagueId,
    required String startRoundName,
    required int startRoundMatchCount,
    required String idPrefix,
    required int nowMs,
    bool includeThirdPlace = false,
  }) {
    String id(String prefix, int index) =>
        '$leagueId-$idPrefix-$prefix-${nowMs}_$index';

    final rounds = <String, List<KnockoutMatch>>{};

    int matchCount = startRoundMatchCount;
    String roundName = startRoundName;

    while (true) {
      final list = <KnockoutMatch>[];
      for (var i = 0; i < matchCount; i++) {
        list.add(
          KnockoutMatch(
            id: id(_shortCode(roundName), i + 1),
            leagueId: leagueId,
            roundName: roundName,
            homeTeamId: null,
            awayTeamId: null,
            homeScore: null,
            awayScore: null,
            status: MatchStatus.scheduled,
            tiebreakWinnerTeamId: null,
            nextMatchId: null,
            loserGoesToMatchId: null,
            isSecondLeg: false,
          ),
        );
      }
      rounds[roundName] = list;

      if (matchCount == 1) break; // Final created

      matchCount = matchCount ~/ 2;
      roundName = _nextRoundName(roundName);
      if (roundName.isEmpty) break;
    }

    // Ordered round names from start to Final.
    final orderedRoundNames = <String>[];
    if (startRoundName == 'Round of 32') {
      orderedRoundNames.addAll([
        'Round of 32',
        'Round of 16',
        'Quarter Finals',
        'Semi Finals',
        'Final',
      ]);
    } else if (startRoundName == 'Round of 16') {
      orderedRoundNames.addAll([
        'Round of 16',
        'Quarter Finals',
        'Semi Finals',
        'Final',
      ]);
    } else if (startRoundName == 'Quarter Finals') {
      orderedRoundNames.addAll(['Quarter Finals', 'Semi Finals', 'Final']);
    } else if (startRoundName == 'Semi Finals') {
      orderedRoundNames.addAll(['Semi Finals', 'Final']);
    } else if (startRoundName == 'Final') {
      orderedRoundNames.addAll(['Final']);
    }

    // Wire nextMatchId between rounds.
    for (var i = 0; i + 1 < orderedRoundNames.length; i++) {
      final from = List<KnockoutMatch>.from(
          rounds[orderedRoundNames[i]] ?? const <KnockoutMatch>[]);
      final to = List<KnockoutMatch>.from(
          rounds[orderedRoundNames[i + 1]] ?? const <KnockoutMatch>[]);

      if (to.isEmpty) continue;

      for (var j = 0; j < from.length; j++) {
        final nextIndex = j ~/ 2;
        if (nextIndex >= to.length) continue;
        from[j] = from[j].copyWith(nextMatchId: to[nextIndex].id);
      }

      rounds[orderedRoundNames[i]] = from;
    }

    // Optional 3rd place if explicitly enabled.
    KnockoutMatch? thirdPlace;
    if (includeThirdPlace && rounds.containsKey('Semi Finals')) {
      thirdPlace = KnockoutMatch(
        id: id('3P', 1),
        leagueId: leagueId,
        roundName: '3rd Place',
        homeTeamId: null,
        awayTeamId: null,
        homeScore: null,
        awayScore: null,
        status: MatchStatus.scheduled,
        tiebreakWinnerTeamId: null,
        nextMatchId: null,
        loserGoesToMatchId: null,
        isSecondLeg: false,
      );

      // Wire semis loser destination.
      final semis = List<KnockoutMatch>.from(
          rounds['Semi Finals'] ?? const <KnockoutMatch>[]);
      if (semis.isNotEmpty) {
        semis[0] = semis[0].copyWith(loserGoesToMatchId: thirdPlace.id);
      }
      if (semis.length > 1) {
        semis[1] = semis[1].copyWith(loserGoesToMatchId: thirdPlace.id);
      }
      rounds['Semi Finals'] = semis;
    }

    // Flatten output in display order.
    final out = <KnockoutMatch>[];
    for (final rn in orderedRoundNames) {
      out.addAll(rounds[rn] ?? const <KnockoutMatch>[]);
    }
    if (thirdPlace != null) out.add(thirdPlace);

    return out;
  }

  static String _pairKey(String a, String b) =>
      (a.compareTo(b) < 0) ? '$a|$b' : '$b|$a';

  static int _seedIndexFromId(String id) {
    final idx = id.lastIndexOf('_');
    if (idx == -1 || idx + 1 >= id.length) return 0;
    final raw = id.substring(idx + 1);
    return int.tryParse(raw) ?? 0;
  }

  static _KoSlot _slotForAdvancement({
    required KnockoutMatch fromMatch,
    required List<KnockoutMatch> allMatches,
  }) {
    final nextId = fromMatch.nextMatchId;
    if (nextId == null) return _KoSlot.home;

    final feeders = allMatches
        .where((m) =>
            m.roundName == fromMatch.roundName && m.nextMatchId == nextId)
        .toList();

    if (feeders.length <= 1) {
      return _KoSlot.home;
    }

    feeders.sort((a, b) {
      final ai = _seedIndexFromId(a.id);
      final bi = _seedIndexFromId(b.id);
      if (ai != bi) return ai.compareTo(bi);
      return a.id.compareTo(b.id);
    });

    final pos = feeders.indexWhere((m) => m.id == fromMatch.id);
    final safePos = max(0, pos);
    return (safePos % 2 == 0) ? _KoSlot.home : _KoSlot.away;
  }

  static List<KnockoutMatch> _advanceWinnerToNext({
    required KnockoutMatch completedMatch,
    required String winnerId,
    required List<KnockoutMatch> allMatches,
  }) {
    final nextId = completedMatch.nextMatchId;
    if (nextId == null) return allMatches;

    final slot =
        _slotForAdvancement(fromMatch: completedMatch, allMatches: allMatches);

    return allMatches.map((m) {
      if (m.id != nextId) return m;

      if (slot == _KoSlot.home) {
        return m.copyWith(homeTeamId: winnerId);
      } else {
        return m.copyWith(awayTeamId: winnerId);
      }
    }).toList();
  }

  static List<KnockoutMatch> _placeLoserToThirdPlace({
    required KnockoutMatch completedSemiFinal,
    required String loserId,
    required List<KnockoutMatch> allMatches,
  }) {
    final thirdId = completedSemiFinal.loserGoesToMatchId;
    if (thirdId == null) return allMatches;

    final semiFeeders = allMatches
        .where((m) =>
            m.roundName == 'Semi Finals' &&
            m.loserGoesToMatchId == thirdId)
        .toList();

    if (semiFeeders.isEmpty) return allMatches;

    semiFeeders.sort((a, b) {
      final ai = _seedIndexFromId(a.id);
      final bi = _seedIndexFromId(b.id);
      if (ai != bi) return ai.compareTo(bi);
      return a.id.compareTo(b.id);
    });

    final pos = semiFeeders.indexWhere((m) => m.id == completedSemiFinal.id);
    final safePos = max(0, pos);
    final slot = (safePos % 2 == 0) ? _KoSlot.home : _KoSlot.away;

    return allMatches.map((m) {
      if (m.id != thirdId) return m;

      if (slot == _KoSlot.home) {
        return m.copyWith(homeTeamId: loserId);
      } else {
        return m.copyWith(awayTeamId: loserId);
      }
    }).toList();
  }

  // ── Existing: UCL GROUP MODEL seeding (UNCHANGED) ─────────────────────────

  /// UCL GROUP MODEL seeding (16 or 32 teams).
  static List<KnockoutMatch> seedKnockoutsFromGroups({
    required String leagueId,
    required Map<String, List<StandingsRow>> groupStandings,
  }) {
    if (groupStandings.isEmpty) return [];

    final now = DateTime.now().millisecondsSinceEpoch;

    final keys = groupStandings.keys.toList()..sort();
    final groupCount = keys.length;

    if (groupCount != 4 && groupCount != 8) return [];

    for (final k in keys) {
      final rows = groupStandings[k] ?? const <StandingsRow>[];
      if (rows.length != 4) return [];
      if (rows.length < 2) return [];
    }

    final winners = <StandingsRow>[
      for (final k in keys) groupStandings[k]![0]
    ];
    final runners = <StandingsRow>[
      for (final k in keys) groupStandings[k]![1]
    ];

    final startRoundName = (groupCount == 8) ? 'Round of 16' : 'Quarter Finals';
    final startMatchCount = (groupCount == 8) ? 8 : 4;

    final tree = _buildKnockoutTree(
      leagueId: leagueId,
      startRoundName: startRoundName,
      startRoundMatchCount: startMatchCount,
      idPrefix: 'GRP',
      nowMs: now,
      includeThirdPlace: false,
    );

    final startRound =
        tree.where((m) => m.roundName == startRoundName).toList();
    if (startRound.length != startMatchCount) return [];

    // Pair groups in twos: A1 vs B2, B1 vs A2, etc.
    final seeded = <KnockoutMatch>[];
    var idx = 0;
    for (var i = 0; i + 1 < winners.length; i += 2) {
      final g1Winner = winners[i];
      final g2Winner = winners[i + 1];
      final g1Runner = runners[i];
      final g2Runner = runners[i + 1];

      seeded.add(
        startRound[idx++].copyWith(
          homeTeamId: g1Winner.teamId,
          awayTeamId: g2Runner.teamId,
        ),
      );
      seeded.add(
        startRound[idx++].copyWith(
          homeTeamId: g2Winner.teamId,
          awayTeamId: g1Runner.teamId,
        ),
      );
    }

    final seededById = {for (final m in seeded) m.id: m};
    return tree.map((m) => seededById[m.id] ?? m).toList();
  }

  // ── Existing: UCL SWISS MODEL seeding (UNCHANGED) ─────────────────────────

  /// UCL SWISS MODEL seeding (18 or 36 teams).
  static List<KnockoutMatch> seedSwissKnockouts({
    required String leagueId,
    required List<StandingsRow> swissStandings,
  }) {
    final n = swissStandings.length;

    if (n != 36 && n != 18) return [];

    final now = DateTime.now().millisecondsSinceEpoch;
    String id(String prefix, int index) =>
        '$leagueId-SWISS-$prefix-${now}_$index';

    if (n == 36) {
      final autoQualifiers = swissStandings.take(8).toList();
      final playoffSeeds = swissStandings.skip(8).take(16).toList();
      if (playoffSeeds.length != 16) return [];

      final tree = _buildKnockoutTree(
        leagueId: leagueId,
        startRoundName: 'Round of 16',
        startRoundMatchCount: 8,
        idPrefix: 'SWISS',
        nowMs: now,
        includeThirdPlace: false,
      );

      final r16 = tree.where((m) => m.roundName == 'Round of 16').toList();
      if (r16.length != 8) return [];

      final seededR16 = <KnockoutMatch>[];
      for (var i = 0; i < 8; i++) {
        seededR16.add(
          r16[i].copyWith(
            homeTeamId: autoQualifiers[i].teamId,
            awayTeamId: null,
          ),
        );
      }

      final playoffMatches = <KnockoutMatch>[];
      int start = 0;
      int end = playoffSeeds.length - 1;

      for (var tieIndex = 0; tieIndex < 8; tieIndex++) {
        final a = playoffSeeds[start++];
        final b = playoffSeeds[end--];
        final r16Index = 7 - tieIndex;

        playoffMatches.add(
          KnockoutMatch(
            id: id('PO1', tieIndex + 1),
            leagueId: leagueId,
            roundName: 'Play-off',
            homeTeamId: a.teamId,
            awayTeamId: b.teamId,
            homeScore: null,
            awayScore: null,
            status: MatchStatus.scheduled,
            tiebreakWinnerTeamId: null,
            nextMatchId: seededR16[r16Index].id,
            loserGoesToMatchId: null,
            isSecondLeg: false,
          ),
        );

        playoffMatches.add(
          KnockoutMatch(
            id: id('PO2', tieIndex + 1),
            leagueId: leagueId,
            roundName: 'Play-off',
            homeTeamId: b.teamId,
            awayTeamId: a.teamId,
            homeScore: null,
            awayScore: null,
            status: MatchStatus.scheduled,
            tiebreakWinnerTeamId: null,
            nextMatchId: seededR16[r16Index].id,
            loserGoesToMatchId: null,
            isSecondLeg: true,
          ),
        );
      }

      final seededById = {for (final m in seededR16) m.id: m};
      final updatedTree = tree.map((m) => seededById[m.id] ?? m).toList();

      return [...playoffMatches, ...updatedTree];
    }

    // n == 18
    final autoQualifiers = swissStandings.take(4).toList();
    final playoffSeeds = swissStandings.skip(4).take(8).toList();
    if (playoffSeeds.length != 8) return [];

    final tree = _buildKnockoutTree(
      leagueId: leagueId,
      startRoundName: 'Quarter Finals',
      startRoundMatchCount: 4,
      idPrefix: 'SWISS',
      nowMs: now,
      includeThirdPlace: false,
    );

    final qf = tree.where((m) => m.roundName == 'Quarter Finals').toList();
    if (qf.length != 4) return [];

    final seededQF = <KnockoutMatch>[];
    for (var i = 0; i < 4; i++) {
      seededQF.add(
        qf[i].copyWith(
          homeTeamId: autoQualifiers[i].teamId,
          awayTeamId: null,
        ),
      );
    }

    final playoffMatches = <KnockoutMatch>[];
    int start = 0;
    int end = playoffSeeds.length - 1;

    for (var tieIndex = 0; tieIndex < 4; tieIndex++) {
      final a = playoffSeeds[start++];
      final b = playoffSeeds[end--];
      final qfIndex = 3 - tieIndex;

      playoffMatches.add(
        KnockoutMatch(
          id: id('PO1', tieIndex + 1),
          leagueId: leagueId,
          roundName: 'Play-off',
          homeTeamId: a.teamId,
          awayTeamId: b.teamId,
          homeScore: null,
          awayScore: null,
          status: MatchStatus.scheduled,
          tiebreakWinnerTeamId: null,
          nextMatchId: seededQF[qfIndex].id,
          loserGoesToMatchId: null,
          isSecondLeg: false,
        ),
      );

      playoffMatches.add(
        KnockoutMatch(
          id: id('PO2', tieIndex + 1),
          leagueId: leagueId,
          roundName: 'Play-off',
          homeTeamId: b.teamId,
          awayTeamId: a.teamId,
          homeScore: null,
          awayScore: null,
          status: MatchStatus.scheduled,
          tiebreakWinnerTeamId: null,
          nextMatchId: seededQF[qfIndex].id,
          loserGoesToMatchId: null,
          isSecondLeg: true,
        ),
      );
    }

    final seededById = {for (final m in seededQF) m.id: m};
    final updatedTree = tree.map((m) => seededById[m.id] ?? m).toList();

    return [...playoffMatches, ...updatedTree];
  }

  // ── NEW: World Cup 32-team knockout seeding (FIFA 2022) ───────────────────

  /// Seeds the knockout bracket for a 32-team World Cup (FIFA 2022 format).
  ///
  /// Bracket structure:
  /// - 8 groups (A–H), top 2 from each group qualify → 16 teams
  /// - Round of 16 (8 matches)
  /// - Quarter-finals (4 matches)
  /// - Semi-finals (2 matches)
  /// - Third Place match (1 match)
  /// - Final (1 match)
  ///
  /// FIFA 2022 R16 pairing (official):
  /// Match 49: 1A vs 2B  |  Match 53: 1C vs 2D
  /// Match 50: 1C vs 2D  |  Match 54: 1E vs 2F  (corrected per FIFA draw)
  /// Match 51: 1B vs 2A  |  Match 55: 1G vs 2H
  /// Match 52: 1D vs 2C  |  Match 56: 1F vs 2E  (corrected per FIFA draw)
  ///
  /// Actual FIFA 2022 R16 pairings (official):
  /// 1A vs 2B, 1C vs 2D, 1B vs 2A, 1D vs 2C,
  /// 1E vs 2F, 1G vs 2H, 1F vs 2E, 1H vs 2G
  ///
  /// Returns empty list if groupStandings does not contain exactly 8 groups
  /// with exactly 4 rows each.
  static List<KnockoutMatch> seedWorldCupKnockouts32({
    required String leagueId,
    required Map<String, List<StandingsRow>> groupStandings,
  }) {
    // Validate: must have exactly 8 groups.
    if (groupStandings.length != 8) return [];

    final keys = groupStandings.keys.toList()..sort();

    // Validate: each group must have exactly 4 rows.
    for (final k in keys) {
      final rows = groupStandings[k] ?? const <StandingsRow>[];
      if (rows.length != 4) return [];
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Build the complete bracket skeleton: R16 → QF → SF → 3P + Final.
    final tree = _buildKnockoutTree(
      leagueId: leagueId,
      startRoundName: 'Round of 16',
      startRoundMatchCount: 8,
      idPrefix: 'WC32',
      nowMs: now,
      includeThirdPlace: true, // World Cup always has a 3rd place match.
    );

    final r16 = tree.where((m) => m.roundName == 'Round of 16').toList();
    if (r16.length != 8) return [];

    // Extract group winners (index 0) and runners-up (index 1) per group.
    // Groups sorted alphabetically: A, B, C, D, E, F, G, H.
    final w = <String, String>{}; // groupKey → winner teamId
    final r = <String, String>{}; // groupKey → runner-up teamId

    for (final k in keys) {
      final rows = groupStandings[k]!;
      w[k] = rows[0].teamId;
      r[k] = rows[1].teamId;
    }

    // Official FIFA 2022 World Cup Round of 16 pairings:
    // Match 1: 1A vs 2B
    // Match 2: 1C vs 2D
    // Match 3: 1B vs 2A
    // Match 4: 1D vs 2C
    // Match 5: 1E vs 2F
    // Match 6: 1G vs 2H
    // Match 7: 1F vs 2E
    // Match 8: 1H vs 2G
    //
    // This mirrors the official FIFA bracket where QF winners feed the correct
    // semi-final slots.
    final pairings = <_WcPairing>[
      _WcPairing(home: w[keys[0]]!, away: r[keys[1]]!), // 1A vs 2B
      _WcPairing(home: w[keys[2]]!, away: r[keys[3]]!), // 1C vs 2D
      _WcPairing(home: w[keys[1]]!, away: r[keys[0]]!), // 1B vs 2A
      _WcPairing(home: w[keys[3]]!, away: r[keys[2]]!), // 1D vs 2C
      _WcPairing(home: w[keys[4]]!, away: r[keys[5]]!), // 1E vs 2F
      _WcPairing(home: w[keys[6]]!, away: r[keys[7]]!), // 1G vs 2H
      _WcPairing(home: w[keys[5]]!, away: r[keys[4]]!), // 1F vs 2E
      _WcPairing(home: w[keys[7]]!, away: r[keys[6]]!), // 1H vs 2G
    ];

    // Apply pairings to R16 slots.
    final seeded = <KnockoutMatch>[];
    for (var i = 0; i < 8; i++) {
      seeded.add(
        r16[i].copyWith(
          homeTeamId: pairings[i].home,
          awayTeamId: pairings[i].away,
        ),
      );
    }

    // Replace seeded R16 matches in the tree.
    final seededById = {for (final m in seeded) m.id: m};
    return tree.map((m) => seededById[m.id] ?? m).toList();
  }

  // ── NEW: World Cup 48-team knockout seeding (FIFA 2026) ───────────────────

  /// Seeds the knockout bracket for a 48-team World Cup (FIFA 2026 format).
  ///
  /// Bracket structure:
  /// - 12 groups (A–L), top 2 from each group = 24 teams
  /// - 8 best 3rd-placed teams from 12 groups = 8 additional teams
  /// - Round of 32 (16 matches): 32 qualified teams
  /// - Round of 16 (8 matches)
  /// - Quarter-finals (4 matches)
  /// - Semi-finals (2 matches)
  /// - Third Place match (1 match)
  /// - Final (1 match)
  ///
  /// FIFA 2026 qualification:
  /// - Group winners (12): automatically qualify to R32.
  /// - Group runners-up (12): automatically qualify to R32.
  /// - Best 8 third-placed teams: ranked by points → GD → GF → teamId.
  ///
  /// FIFA 2026 R32 pairing convention (based on published FIFA format):
  /// Group winners are paired against the 8 best third-placed teams.
  /// Runners-up are paired against each other in adjacent group pairs.
  ///
  /// Returns empty list if groupStandings does not contain exactly 12 groups
  /// with exactly 4 rows each.
  static List<KnockoutMatch> seedWorldCupKnockouts48({
    required String leagueId,
    required Map<String, List<StandingsRow>> groupStandings,
  }) {
    // Validate: must have exactly 12 groups.
    if (groupStandings.length != 12) return [];

    final keys = groupStandings.keys.toList()..sort();

    // Validate: each group must have exactly 4 rows.
    for (final k in keys) {
      final rows = groupStandings[k] ?? const <StandingsRow>[];
      if (rows.length != 4) return [];
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Build the complete bracket skeleton: R32 → R16 → QF → SF → 3P + Final.
    final tree = _buildKnockoutTree(
      leagueId: leagueId,
      startRoundName: 'Round of 32',
      startRoundMatchCount: 16,
      idPrefix: 'WC48',
      nowMs: now,
      includeThirdPlace: true, // World Cup always has a 3rd place match.
    );

    final r32 = tree.where((m) => m.roundName == 'Round of 32').toList();
    if (r32.length != 16) return [];

    // Collect qualified teams.
    // 12 winners + 12 runners-up + 8 best third-placed = 32 teams.
    final groupWinners = <StandingsRow>[];
    final groupRunnersUp = <StandingsRow>[];
    final allThirdPlaced = <StandingsRow>[];

    for (final k in keys) {
      final rows = groupStandings[k]!;
      groupWinners.add(rows[0]);
      groupRunnersUp.add(rows[1]);
      if (rows.length >= 3) allThirdPlaced.add(rows[2]);
    }

    // Select 8 best third-placed teams by FIFA tie-breaker rules:
    // 1) Points DESC, 2) GD DESC, 3) GF DESC, 4) teamId ASC (stable)
    allThirdPlaced.sort((a, b) {
      final pts = b.finalPoints.compareTo(a.finalPoints);
      if (pts != 0) return pts;
      final gd = b.gd.compareTo(a.gd);
      if (gd != 0) return gd;
      final gf = b.gf.compareTo(a.gf);
      if (gf != 0) return gf;
      return a.teamId.compareTo(b.teamId);
    });

    // Take the 8 best third-placed teams.
    final bestThird = allThirdPlaced.take(8).toList();

    if (bestThird.length < 8) {
      // Not enough third-placed teams yet — bracket cannot be seeded.
      return [];
    }

    // FIFA 2026 R32 pairing convention:
    //
    // The 16 R32 matches pair:
    // - Match 1..8: Each group winner vs one of the 8 best 3rd-placed teams
    //   (winners from groups A–H paired with best 3rd teams ranked 1–8).
    // - Match 9..16: Runners-up pairs from adjacent groups
    //   (runners-up from groups A–L paired in sequence: 2A vs 2B, 2C vs 2D, ...).
    //
    // This follows the FIFA 2026 published draw methodology where group winners
    // get favorable bracket positioning.

    // Pair 1: 8 winners (groups A–H) vs 8 best 3rd-placed.
    // Pair 2: 4 runners-up pairs from groups A–H (2A vs 2B, 2C vs 2D, etc.)
    // Pair 3: 4 winners (groups I–L) vs runners-up (groups I–L) paired.
    //
    // Final R32 structure (16 matches):
    // Slots 0–7:  Winners of groups A–H vs Best 3rd-placed teams (ranked 1–8)
    // Slots 8–11: Runner-up pairs: 2A vs 2B, 2C vs 2D, 2E vs 2F, 2G vs 2H
    // Slots 12–15: Winners I,J,K,L vs Runners-up I,J,K,L
    //   (1I vs 2J, 1K vs 2L, 1J vs 2I, 1L vs 2K)

    final seeded = <KnockoutMatch>[];

    // Slots 0–7: Winners A–H vs Best 3rd ranked 1–8.
    for (var i = 0; i < 8; i++) {
      seeded.add(
        r32[i].copyWith(
          homeTeamId: groupWinners[i].teamId,
          awayTeamId: bestThird[i].teamId,
        ),
      );
    }

    // Slots 8–11: Runners-up A–H paired in adjacent groups.
    // 2A vs 2B (slot 8), 2C vs 2D (slot 9), 2E vs 2F (slot 10), 2G vs 2H (slot 11)
    for (var i = 0; i < 4; i++) {
      final homeRunner = groupRunnersUp[i * 2];
      final awayRunner = groupRunnersUp[i * 2 + 1];
      seeded.add(
        r32[8 + i].copyWith(
          homeTeamId: homeRunner.teamId,
          awayTeamId: awayRunner.teamId,
        ),
      );
    }

    // Slots 12–15: Winners I–L vs Runners-up I–L (cross-paired).
    // 1I vs 2J (slot 12), 1K vs 2L (slot 13), 1J vs 2I (slot 14), 1L vs 2K (slot 15)
    final winnersIL = groupWinners.sublist(8, 12); // I, J, K, L
    final runnersIL = groupRunnersUp.sublist(8, 12); // I, J, K, L

    seeded.add(
      r32[12].copyWith(
        homeTeamId: winnersIL[0].teamId, // 1I
        awayTeamId: runnersIL[1].teamId, // 2J
      ),
    );
    seeded.add(
      r32[13].copyWith(
        homeTeamId: winnersIL[2].teamId, // 1K
        awayTeamId: runnersIL[3].teamId, // 2L
      ),
    );
    seeded.add(
      r32[14].copyWith(
        homeTeamId: winnersIL[1].teamId, // 1J
        awayTeamId: runnersIL[0].teamId, // 2I
      ),
    );
    seeded.add(
      r32[15].copyWith(
        homeTeamId: winnersIL[3].teamId, // 1L
        awayTeamId: runnersIL[2].teamId, // 2K
      ),
    );

    // Replace seeded R32 matches in the tree.
    final seededById = {for (final m in seeded) m.id: m};
    return tree.map((m) => seededById[m.id] ?? m).toList();
  }

  // ── Existing: processMatchResult (UNCHANGED) ───────────────────────────────

  /// Automatic advancement after a KO match is confirmed.
  /// Handles: Play-off two-legged ties, single-match R16/QF/SF/Final,
  /// and now also Round of 32 (World Cup 48-team).
  static List<KnockoutMatch> processMatchResult({
    required KnockoutMatch completedMatch,
    required List<KnockoutMatch> allMatches,
  }) {
    if (!completedMatch.isFinished) return allMatches;

    // Two-legged Play-off aggregate handling (UCL Swiss).
    if (completedMatch.roundName == 'Play-off') {
      if (!completedMatch.isSecondLeg) return allMatches;

      final hId = completedMatch.homeTeamId;
      final aId = completedMatch.awayTeamId;
      if (hId == null || aId == null) return allMatches;

      final nextId = completedMatch.nextMatchId;
      if (nextId == null) return allMatches;

      final tieKey = _pairKey(hId, aId);

      KnockoutMatch? firstLeg;
      for (final m in allMatches) {
        if (m.roundName != 'Play-off') continue;
        if (m.isSecondLeg) continue;
        if (m.nextMatchId != nextId) continue;
        if (m.homeTeamId == null || m.awayTeamId == null) continue;
        if (_pairKey(m.homeTeamId!, m.awayTeamId!) != tieKey) continue;
        firstLeg = m;
        break;
      }

      if (firstLeg == null) return allMatches;
      if (!firstLeg.isFinished) return allMatches;

      final totals = <String, int>{hId: 0, aId: 0};

      void add(KnockoutMatch m) {
        final home = m.homeTeamId!;
        final away = m.awayTeamId!;
        totals[home] = (totals[home] ?? 0) + m.homeScore!;
        totals[away] = (totals[away] ?? 0) + m.awayScore!;
      }

      add(firstLeg);
      add(completedMatch);

      final hTot = totals[hId] ?? 0;
      final aTot = totals[aId] ?? 0;

      String? winner;
      if (hTot > aTot) {
        winner = hId;
      } else if (aTot > hTot) {
        winner = aId;
      } else {
        winner = completedMatch.tiebreakWinnerTeamId;
      }

      if (winner == null) return allMatches;

      return allMatches.map((m) {
        if (m.id != nextId) return m;

        final nextHome = m.homeTeamId;
        final nextAway = m.awayTeamId;

        if (nextHome == null && nextAway != null) {
          return m.copyWith(homeTeamId: winner);
        }
        if (nextAway == null && nextHome != null) {
          return m.copyWith(awayTeamId: winner);
        }
        if (nextHome == null && nextAway == null) {
          return m.copyWith(homeTeamId: winner);
        }
        if (nextAway != winner) return m.copyWith(awayTeamId: winner);
        return m;
      }).toList();
    }

    // Standard single-match advancement for R32/R16/QF/SF/Final.
    // The R32 round name is now handled transparently by the same logic
    // since it follows the same winner-advances pattern.
    final winnerId = completedMatch.winnerTeamId;
    if (winnerId == null) return allMatches;

    final loserId = (winnerId == completedMatch.homeTeamId)
        ? completedMatch.awayTeamId
        : completedMatch.homeTeamId;

    var updated = allMatches;

    if (completedMatch.nextMatchId != null) {
      updated = _advanceWinnerToNext(
        completedMatch: completedMatch,
        winnerId: winnerId,
        allMatches: updated,
      );
    }

    if (loserId != null &&
        completedMatch.roundName == 'Semi Finals' &&
        completedMatch.loserGoesToMatchId != null) {
      updated = _placeLoserToThirdPlace(
        completedSemiFinal: completedMatch,
        loserId: loserId,
        allMatches: updated,
      );
    }

    return updated;
  }
}

// ---------------------------------------------------------------------------
// Internal helper — World Cup match pairing value object.
// ---------------------------------------------------------------------------

/// Simple value object used internally during World Cup R16/R32 seeding.
class _WcPairing {
  final String home;
  final String away;
  const _WcPairing({required this.home, required this.away});
}