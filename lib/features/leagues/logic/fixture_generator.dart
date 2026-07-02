// lib/features/leagues/logic/fixture_generator.dart
//
// MODIFIED: Added World Cup group stage fixture generation.
//
// New public method:
//   - generateWorldCupGroupStage() — generates single round-robin fixtures
//     for all World Cup groups (8 groups × 4 teams for FIFA 2022,
//     12 groups × 4 teams for FIFA 2026).
//
// All existing methods (generateRoundRobin, generateClassicLeagueFixtures,
// generateUclGroupStage) are completely unchanged.

import 'package:uuid/uuid.dart';

import '../domain/algorithms/round_robin.dart';
import '../models/enums.dart';
import '../models/fixture_match.dart';
import '../models/league_settings.dart';
import '../models/team.dart';

/// Generates league fixtures.
///
/// Supported here:
/// - Classic round-robin (single table)
/// - UCL Group stage (groups of 4) using Team.groupId
/// - World Cup group stage (8 or 12 groups of 4) using Team.groupId
///
/// NOT supported here:
/// - Swiss pairing (handled by SwissPairingEngine)
/// - Knockout logic (handled by TournamentController seeding + admin updates)
class FixtureGenerator {
  static final _uuid = Uuid();

  // ── Existing: Basic round-robin (UNCHANGED) ────────────────────────────────

  /// Basic round-robin fixture list (single table).
  ///
  /// - Does NOT mutate input
  /// - Supports odd number of teams (bye rounds)
  static List<FixtureMatch> generateRoundRobin({
    required String leagueId,
    required List<String> teamIds,
    String? groupId,
  }) {
    final teams = List<String>.from(teamIds);
    // Add BYE if odd
    if (teams.length.isOdd) {
      teams.add('__BYE__');
    }

    final int numTeams = teams.length;
    final int rounds = numTeams - 1;
    final List<FixtureMatch> fixtures = [];

    final rotation = List<String>.from(teams);

    for (int round = 1; round <= rounds; round++) {
      for (int i = 0; i < numTeams / 2; i++) {
        final home = rotation[i];
        final away = rotation[numTeams - 1 - i];

        if (home == '__BYE__' || away == '__BYE__') continue;

        fixtures.add(
          FixtureMatch(
            id: _uuid.v4(),
            leagueId: leagueId,
            groupId: groupId,
            roundNumber: round,
            homeTeamId: home,
            awayTeamId: away,
            homeScore: null,
            awayScore: null,
            status: MatchStatus.scheduled,
            sortIndex: i,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          ),
        );
      }

      // Rotate teams (keep first fixed)
      final last = rotation.removeLast();
      rotation.insert(1, last);
    }

    return fixtures;
  }

  // ── Existing: Classic League (UNCHANGED) ──────────────────────────────────

  /// Classic League fixtures using the deterministic RoundRobinGenerator
  /// (supports doubleRoundRobin).
  static List<FixtureMatch> generateClassicLeagueFixtures({
    required String leagueId,
    required List<Team> teams,
    required bool doubleRoundRobin,
  }) {
    if (teams.length < 2) return [];
    final teamIds = teams.map((t) => t.id).toList();

    return RoundRobinGenerator.generate(
      leagueId: leagueId,
      teamIds: teamIds,
      doubleRoundRobin: doubleRoundRobin,
      groupId: null,
      startRoundNumber: 1,
    );
  }

  // ── Existing: UCL Group Stage (UNCHANGED) ─────────────────────────────────

  /// UCL Group Stage fixture generation.
  ///
  /// Enforced constraints (as per your spec):
  /// - total teams must be 16 or 32
  /// - groups must be of size 4
  /// - Team.groupId must be assigned and must create exactly:
  ///   - 4 groups (for 16 teams) OR
  ///   - 8 groups (for 32 teams)
  ///
  /// Each group uses RoundRobinGenerator (supports doubleRoundRobin).
  /// Rounds start at 1 for ALL groups (Matchday 1..6 in parallel).
  static List<FixtureMatch> generateUclGroupStage({
    required String leagueId,
    required List<Team> teams,
    required bool doubleRoundRobin,
    int groupSize = 4,
  }) {
    if (!(teams.length == 16 || teams.length == 32)) return [];
    if (groupSize != 4) return [];
    final expectedGroups = teams.length ~/ groupSize;
    if (!(expectedGroups == 4 || expectedGroups == 8)) return [];

    // Group teams by Team.groupId
    final byGroup = <String, List<Team>>{};
    for (final t in teams) {
      final gid = (t.groupId ?? '').trim();
      if (gid.isEmpty) return []; // must be assigned
      byGroup.putIfAbsent(gid, () => []).add(t);
    }

    if (byGroup.length != expectedGroups) return [];

    // Enforce each group has exactly 4 teams
    for (final entry in byGroup.entries) {
      if (entry.value.length != groupSize) return [];
    }

    // Generate fixtures per group
    final allFixtures = <FixtureMatch>[];

    final groupKeys = byGroup.keys.toList()..sort();
    for (final groupId in groupKeys) {
      final ids = byGroup[groupId]!.map((t) => t.id).toList();

      final groupFixtures = RoundRobinGenerator.generate(
        leagueId: leagueId,
        teamIds: ids,
        doubleRoundRobin: doubleRoundRobin,
        groupId: groupId,
        startRoundNumber: 1,
      );

      allFixtures.addAll(groupFixtures);
    }

    return allFixtures;
  }

  // ── NEW: World Cup Group Stage ─────────────────────────────────────────────

  /// World Cup Group Stage fixture generation.
  ///
  /// Supports both FIFA formats:
  /// - FIFA 2022 (32 teams): 8 groups × 4 teams, single round-robin
  ///   → 3 matchdays per group, 6 matches per group, 48 matches total
  /// - FIFA 2026 (48 teams): 12 groups × 4 teams, single round-robin
  ///   → 3 matchdays per group, 6 matches per group, 72 matches total
  ///
  /// IMPORTANT:
  /// - World Cup ALWAYS uses single round-robin (doubleRoundRobin = false).
  ///   Each team plays the other 3 teams in their group exactly once.
  /// - Team.groupId must be assigned before calling this method.
  ///   Use WorldCupGroupAssigner to assign groups automatically.
  ///
  /// Enforced constraints:
  /// - total teams must be 32 (FIFA 2022) or 48 (FIFA 2026)
  /// - groups must be of size 4
  /// - Team.groupId must be assigned creating exactly 8 or 12 groups
  ///
  /// Returns an empty list if constraints are violated.
  static List<FixtureMatch> generateWorldCupGroupStage({
    required String leagueId,
    required List<Team> teams,
    required WorldCupFormat worldCupFormat,
  }) {
    // Validate team count matches the chosen format.
    final expectedTeams = worldCupFormat.teamCount;
    if (teams.length != expectedTeams) {
      assert(false,
          '[FixtureGenerator.generateWorldCupGroupStage] '
          'Expected $expectedTeams teams for $worldCupFormat, '
          'got ${teams.length}');
      return [];
    }

    const groupSize = 4;
    final expectedGroupCount = worldCupFormat.groupCount;

    // Group teams by Team.groupId.
    final byGroup = <String, List<Team>>{};
    for (final t in teams) {
      final gid = (t.groupId ?? '').trim();
      if (gid.isEmpty) {
        // All teams must have a group assigned.
        assert(false,
            '[FixtureGenerator.generateWorldCupGroupStage] '
            'Team ${t.id} (${t.name}) has no groupId assigned.');
        return [];
      }
      byGroup.putIfAbsent(gid, () => []).add(t);
    }

    // Validate group count.
    if (byGroup.length != expectedGroupCount) {
      assert(false,
          '[FixtureGenerator.generateWorldCupGroupStage] '
          'Expected $expectedGroupCount groups, got ${byGroup.length}');
      return [];
    }

    // Validate each group has exactly 4 teams.
    for (final entry in byGroup.entries) {
      if (entry.value.length != groupSize) {
        assert(false,
            '[FixtureGenerator.generateWorldCupGroupStage] '
            'Group ${entry.key} has ${entry.value.length} teams, '
            'expected $groupSize.');
        return [];
      }
    }

    // Generate single round-robin fixtures for each group.
    // World Cup uses single round-robin (3 matches per team, 6 per group).
    final allFixtures = <FixtureMatch>[];
    final groupKeys = byGroup.keys.toList()..sort();

    for (final groupId in groupKeys) {
      final ids = byGroup[groupId]!.map((t) => t.id).toList();

      // RoundRobinGenerator with doubleRoundRobin = false generates
      // exactly 3 rounds (Matchday 1, 2, 3) for 4 teams.
      final groupFixtures = RoundRobinGenerator.generate(
        leagueId: leagueId,
        teamIds: ids,
        doubleRoundRobin: false, // World Cup: single round-robin only.
        groupId: groupId,
        startRoundNumber: 1,
      );

      allFixtures.addAll(groupFixtures);
    }

    return allFixtures;
  }
}