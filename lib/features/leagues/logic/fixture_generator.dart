import 'package:uuid/uuid.dart';

import '../domain/algorithms/round_robin.dart';
import '../models/enums.dart';
import '../models/fixture_match.dart';
import '../models/team.dart';

/// Generates league fixtures.
///
/// Supported here:
/// - Classic round-robin (single table)
/// - UCL Group stage (groups of 4) using Team.groupId
///
/// NOT supported here:
/// - Swiss pairing (handled by SwissPairingEngine)
/// - Knockout logic (handled by TournamentController seeding + admin updates)
class FixtureGenerator {
static final _uuid = Uuid();
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
/// Classic League fixtures using the deterministic RoundRobinGenerator (supports doubleRoundRobin).
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
/// UCL Group Stage fixture generation.
///
/// Enforced constraints (as per your spec):
/// - total teams must be 16 or 32
/// - groups must be of size 4
/// - Team.groupId must be assigned and must create exactly:
/// - 4 groups (for 16 teams) OR
/// - 8 groups (for 32 teams)
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
}
