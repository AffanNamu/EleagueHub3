// web_client/lib/algorithms/deterministicKnockoutId.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/algorithms/deterministicKnockoutId.test.ts`.
// PHASE C.1 priority 2: mirrors test/deterministic_knockout_id_test.dart --
// see tournamentController.ts's buildKnockoutTree id() closure comment for
// the full rationale (timestamp dropped from bracket-seeding match ids so
// a concurrent/retried first-time generation converges instead of minting
// a duplicate bracket).

import {
  seedTopNKnockouts,
  seedSwissKnockouts,
  seedKnockoutsFromGroups,
  processMatchResult,
  StandingsRowLike,
} from './tournamentController';

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

function row(teamId: string, w = 0): StandingsRowLike {
  return { teamId, finalPoints: w * 3, gd: 0, gf: 0 };
}

// seedTopNKnockouts
{
  const teams = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  const first = seedTopNKnockouts({ leagueId: 'league1', rankedTeamIds: teams });
  const second = seedTopNKnockouts({ leagueId: 'league1', rankedTeamIds: teams });
  assertEqual(
    first.map((m) => m.id),
    second.map((m) => m.id),
    'seedTopNKnockouts: repeated generation with the same input produces identical ids',
  );

  const ids = first.map((m) => m.id);
  assertEqual(new Set(ids).size, ids.length, 'seedTopNKnockouts: every match in one generation has a unique id');

  for (const m of first) {
    assertTrue(m.id.startsWith('league1-TOPN-'), `id ${m.id} keeps the expected prefix`);
    assertEqual(/-\d{10,}_/.test(m.id), false, `id ${m.id} no longer embeds a timestamp`);
  }
}

{
  const teams = ['A', 'B', 'C', 'D'];
  const league1 = seedTopNKnockouts({ leagueId: 'league1', rankedTeamIds: teams });
  const league2 = seedTopNKnockouts({ leagueId: 'league2', rankedTeamIds: teams });
  const overlap = league1.map((m) => m.id).filter((id) => league2.some((m) => m.id === id));
  assertEqual(overlap, [], 'seedTopNKnockouts: different leagues never collide even with an identical bracket shape');
}

// Legitimate bracket advancement still works after the id change.
{
  const bracket = seedTopNKnockouts({ leagueId: 'league1', rankedTeamIds: ['A', 'B', 'C', 'D'] });
  const semis = bracket.filter((m) => m.roundName === 'Semi Finals');
  assertEqual(semis.length, 2, 'seedTopNKnockouts: 4-team bracket has 2 semi-finals');

  const semi1 = semis.find((m) => m.homeTeamId === 'A')!;
  const completedSemi1 = { ...semi1, homeScore: 2, awayScore: 0, status: 'completed' as const };

  const afterSemi1 = processMatchResult({
    completedMatch: completedSemi1,
    allMatches: bracket.map((m) => (m.id === semi1.id ? completedSemi1 : m)),
  });

  const final_ = afterSemi1.find((m) => m.roundName === 'Final')!;
  assertTrue(final_.homeTeamId === 'A' || final_.awayTeamId === 'A', 'winner of semi 1 fills the correct Final slot');
}

// seedSwissKnockouts
{
  const standings: StandingsRowLike[] = Array.from({ length: 18 }, (_, i) => row(`t${i}`, 18 - i));
  const first = seedSwissKnockouts({ leagueId: 'league1', swissStandings: standings });
  const second = seedSwissKnockouts({ leagueId: 'league1', swissStandings: standings });
  assertEqual(
    first.map((m) => m.id),
    second.map((m) => m.id),
    'seedSwissKnockouts: repeated generation with the same input produces identical ids',
  );

  const ids = first.map((m) => m.id);
  assertEqual(new Set(ids).size, ids.length, 'seedSwissKnockouts: Play-off ids never collide with Quarter Finals ids');
}

// seedKnockoutsFromGroups
{
  const groups: Record<string, StandingsRowLike[]> = {
    'Group A': [row('A1', 3), row('A2', 2), row('A3', 1), row('A4', 0)],
    'Group B': [row('B1', 3), row('B2', 2), row('B3', 1), row('B4', 0)],
    'Group C': [row('C1', 3), row('C2', 2), row('C3', 1), row('C4', 0)],
    'Group D': [row('D1', 3), row('D2', 2), row('D3', 1), row('D4', 0)],
  };
  const first = seedKnockoutsFromGroups({ leagueId: 'league1', groupStandings: groups });
  const second = seedKnockoutsFromGroups({ leagueId: 'league1', groupStandings: groups });
  assertEqual(
    first.map((m) => m.id),
    second.map((m) => m.id),
    'seedKnockoutsFromGroups: repeated generation with the same group standings produces identical ids',
  );
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll deterministicKnockoutId assertions passed.');
}
