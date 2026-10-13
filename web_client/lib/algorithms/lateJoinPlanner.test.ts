// web_client/lib/algorithms/lateJoinPlanner.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/algorithms/lateJoinPlanner.test.ts`.
// PHASE D: mirrors test/late_join_planner_test.dart scenario for scenario.

import {
  planLateJoin,
  supportsLateJoinFormat,
  LateJoinUnsupportedFormatError,
  LateJoinTeamAlreadyInLeagueError,
} from './lateJoinPlanner';
import { FixtureMatch } from '@/lib/models/leagueDetails';
import { LeagueFormat } from '@/lib/models/leagueFormat';

let failures = 0;

function assertEqual<T>(actual: T, expected: T, label: string) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) {
    failures++;
    console.error(`FAIL: ${label}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
  } else {
    console.log(`ok - ${label}`);
  }
}

function assertTrue(actual: boolean, label: string) {
  assertEqual(actual, true, label);
}

function assertThrows(fn: () => void, label: string) {
  try {
    fn();
    failures++;
    console.error(`FAIL: ${label}\n  expected a throw, but none occurred`);
  } catch {
    console.log(`ok - ${label}`);
  }
}

function match({
  id,
  home,
  away,
  round = 1,
  status = 'scheduled',
  homeScore = null,
  awayScore = null,
}: {
  id: string;
  home: string;
  away: string;
  round?: number;
  status?: FixtureMatch['status'];
  homeScore?: number | null;
  awayScore?: number | null;
}): FixtureMatch {
  return {
    id,
    leagueId: 'league1',
    groupId: null,
    roundNumber: round,
    homeTeamId: home,
    awayTeamId: away,
    homeScore,
    awayScore,
    status,
    sortIndex: 0,
    updatedAtMs: 0,
  };
}

// supportsLateJoinFormat
assertTrue(supportsLateJoinFormat('classic'), 'only Classic League is supported: classic');
assertEqual(supportsLateJoinFormat('uclGroup'), false, 'only Classic League is supported: uclGroup');
assertEqual(supportsLateJoinFormat('uclSwiss'), false, 'only Classic League is supported: uclSwiss');
assertEqual(supportsLateJoinFormat('worldCup'), false, 'only Classic League is supported: worldCup');
assertEqual(supportsLateJoinFormat('directKnockout'), false, 'only Classic League is supported: directKnockout');

// unsupported formats throw, naming the format
for (const format of ['uclGroup', 'uclSwiss', 'worldCup', 'directKnockout'] as LeagueFormat[]) {
  let caught: unknown = null;
  try {
    planLateJoin({
      format,
      leagueId: 'league1',
      existingMatches: [],
      existingTeamIds: ['A', 'B'],
      newTeamId: 'NEW',
      doubleRoundRobin: false,
    });
  } catch (e) {
    caught = e;
  }
  const isUnsupported = caught instanceof LateJoinUnsupportedFormatError;
  assertTrue(isUnsupported, `${format}: throws LateJoinUnsupportedFormatError`);
  if (isUnsupported) {
    assertEqual((caught as LateJoinUnsupportedFormatError).format, format, `${format}: error names the format`);
  }
}

// team already in the league is rejected
assertThrows(
  () =>
    planLateJoin({
      format: 'classic',
      leagueId: 'league1',
      existingMatches: [],
      existingTeamIds: ['A', 'B'],
      newTeamId: 'A',
      doubleRoundRobin: false,
    }),
  'team already in the league is rejected',
);
{
  let caught: unknown = null;
  try {
    planLateJoin({ format: 'classic', leagueId: 'league1', existingMatches: [], existingTeamIds: ['A'], newTeamId: 'A', doubleRoundRobin: false });
  } catch (e) {
    caught = e;
  }
  assertTrue(caught instanceof LateJoinTeamAlreadyInLeagueError, 'already-in-league error has the right type');
}

// new fixtures against every existing team, single round-robin
{
  const existing = [
    match({ id: 'm1', home: 'A', away: 'B', round: 1, status: 'completed', homeScore: 1, awayScore: 0 }),
    match({ id: 'm2', home: 'A', away: 'C', round: 2 }),
  ];

  const preview = planLateJoin({
    format: 'classic',
    leagueId: 'league1',
    existingMatches: existing,
    existingTeamIds: ['A', 'B', 'C'],
    newTeamId: 'NEW',
    doubleRoundRobin: false,
  });

  assertEqual(preview.completedMatchCount, 1, 'completedMatchCount');
  assertEqual(preview.futureMatchCount, 1, 'futureMatchCount');
  assertEqual(preview.newFixtures.length, 3, 'newFixtureCount');
  assertEqual(preview.existingMatchesAffectedCount, 0, 'existingMatchesAffectedCount');

  for (const m of preview.newFixtures) {
    assertTrue(m.homeTeamId === 'NEW' || m.awayTeamId === 'NEW', `fixture ${m.id} involves the new team`);
  }

  const existingIds = new Set(existing.map((m) => m.id));
  for (const m of preview.newFixtures) {
    assertEqual(existingIds.has(m.id), false, `new fixture ${m.id} does not collide with an existing id`);
  }
}

// double round-robin creates a home and an away fixture per existing team
{
  const preview = planLateJoin({
    format: 'classic',
    leagueId: 'league1',
    existingMatches: [],
    existingTeamIds: ['A', 'B'],
    newTeamId: 'NEW',
    doubleRoundRobin: true,
  });

  assertEqual(preview.newFixtures.length, 4, 'double round-robin: 4 new fixtures for 2 existing teams');
  const aLegs = preview.newFixtures.filter((m) => m.homeTeamId === 'A' || m.awayTeamId === 'A');
  assertEqual(aLegs.length, 2, 'double round-robin: 2 legs against A');
  assertTrue(aLegs.some((m) => m.homeTeamId === 'NEW' && m.awayTeamId === 'A'), 'double round-robin: NEW home vs A leg exists');
  assertTrue(aLegs.some((m) => m.homeTeamId === 'A' && m.awayTeamId === 'NEW'), 'double round-robin: A home vs NEW leg exists');
}

// new fixtures placed in brand-new round numbers after the existing max round
{
  const existing = [match({ id: 'm1', home: 'A', away: 'B', round: 5, status: 'completed', homeScore: 2, awayScore: 2 })];
  const preview = planLateJoin({
    format: 'classic',
    leagueId: 'league1',
    existingMatches: existing,
    existingTeamIds: ['A', 'B'],
    newTeamId: 'NEW',
    doubleRoundRobin: false,
  });
  for (const m of preview.newFixtures) {
    assertTrue(m.roundNumber > 5, `fixture ${m.id} round ${m.roundNumber} is after the existing max round`);
  }
}

// no existing match (played or not) is ever included in the new-fixtures list
{
  const existing = [
    match({ id: 'm1', home: 'A', away: 'B', round: 1, status: 'completed', homeScore: 3, awayScore: 1 }),
    match({ id: 'm2', home: 'B', away: 'A', round: 2 }),
  ];
  const preview = planLateJoin({
    format: 'classic',
    leagueId: 'league1',
    existingMatches: existing,
    existingTeamIds: ['A', 'B'],
    newTeamId: 'NEW',
    doubleRoundRobin: false,
  });
  const newIds = new Set(preview.newFixtures.map((m) => m.id));
  assertEqual(newIds.has('m1'), false, 'm1 is never in the new-fixtures list');
  assertEqual(newIds.has('m2'), false, 'm2 is never in the new-fixtures list');
}

// deterministic id matches the same scheme a regular generation run uses
{
  const preview = planLateJoin({
    format: 'classic',
    leagueId: 'league1',
    existingMatches: [],
    existingTeamIds: ['A'],
    newTeamId: 'NEW',
    doubleRoundRobin: false,
  });
  assertEqual(preview.newFixtures[0].id, 'league1-RR-POOL-1-NEW-A', 'deterministic id matches the regular generation scheme');
}

// planning twice in a row from the same unchanged state is stable (idempotent)
{
  const existing = [match({ id: 'm1', home: 'A', away: 'B', round: 1, status: 'completed', homeScore: 1, awayScore: 1 })];
  const first = planLateJoin({ format: 'classic', leagueId: 'league1', existingMatches: existing, existingTeamIds: ['A', 'B'], newTeamId: 'NEW', doubleRoundRobin: false });
  const second = planLateJoin({ format: 'classic', leagueId: 'league1', existingMatches: existing, existingTeamIds: ['A', 'B'], newTeamId: 'NEW', doubleRoundRobin: false });
  assertEqual(
    first.newFixtures.map((m) => m.id),
    second.newFixtures.map((m) => m.id),
    'repeated planning from the same state is stable',
  );
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll lateJoinPlanner assertions passed.');
}
