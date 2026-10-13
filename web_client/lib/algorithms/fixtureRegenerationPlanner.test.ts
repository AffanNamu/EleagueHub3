// web_client/lib/algorithms/fixtureRegenerationPlanner.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/algorithms/fixtureRegenerationPlanner.test.ts`.
// PHASE C.1: mirrors test/fixture_regeneration_planner_test.dart scenario
// for scenario, plus the explicit scenarios called out in the follow-up
// brief (legacy-UUID id preservation, no duplication, deterministic id for
// a genuinely new pairing, obsolete-unplayed pruning, played-match
// protection, and repeated-generation stability).

import { planFixtureRegeneration } from './fixtureRegenerationPlanner';
import { FixtureRegenerationBlockedError } from './fixtureRegenerationGuard';
import { FixtureMatch } from '@/lib/models/leagueDetails';

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

// fresh league with no existing matches: generates everything as-is
{
  const generated = [match({ id: 'gen-1', home: 'A', away: 'B' }), match({ id: 'gen-2', home: 'C', away: 'D' })];
  const plan = planFixtureRegeneration({ existing: [], generated });
  assertEqual(plan.idsToDelete, [], 'fresh league: nothing to delete');
  assertEqual(
    plan.toWrite.map((m) => m.id),
    ['gen-1', 'gen-2'],
    'fresh league: generated ids pass through unchanged (== new fixture receives its deterministic id)',
  );
}

// no matches played yet: regeneration allowed, unchanged pairings keep old id, obsolete unplayed pairing is pruned
{
  const existing = [match({ id: 'old-1', home: 'A', away: 'B', round: 1 }), match({ id: 'old-2', home: 'C', away: 'D', round: 1 })];
  // Team D was removed and replaced with E -- same shape (2 matches, round 1)
  // but a different pairing for the second match.
  const generated = [match({ id: 'fresh-1', home: 'A', away: 'B', round: 1 }), match({ id: 'fresh-2', home: 'C', away: 'E', round: 1 })];

  const plan = planFixtureRegeneration({ existing, generated });

  const ab = plan.toWrite.find((m) => m.homeTeamId === 'A' && m.awayTeamId === 'B')!;
  assertEqual(ab.id, 'old-1', 'unchanged pairing keeps its existing (legacy-style) id, not duplicated under a new id');

  const ce = plan.toWrite.find((m) => m.homeTeamId === 'C' && m.awayTeamId === 'E')!;
  assertEqual(ce.id, 'fresh-2', 'new pairing keeps the generator\'s fresh/deterministic id');

  assertEqual(plan.idsToDelete, ['old-2'], 'obsolete unplayed pairing (C-vs-D no longer in the new set) is pruned');
}

// legacy random-UUID existing id is preserved verbatim for an unchanged pairing
{
  const legacyUuid = 'a1b2c3d4-5678-90ab-cdef-1234567890ab';
  const existing = [match({ id: legacyUuid, home: 'A', away: 'B', round: 1 })];
  const generated = [match({ id: 'league1-RR-POOL-1-A-B', home: 'A', away: 'B', round: 1 })];

  const plan = planFixtureRegeneration({ existing, generated });

  assertEqual(plan.toWrite[0].id, legacyUuid, 'legacy random-UUID fixture retains its existing id');
  assertEqual(plan.toWrite.length, 1, 'no duplicate document is created alongside the legacy one');
  assertEqual(plan.idsToDelete, [], 'legacy doc is reused, not deleted');
}

// any existing match already played: regeneration is blocked and nothing is planned for deletion
{
  const existing = [
    match({ id: 'old-1', home: 'A', away: 'B', status: 'completed', homeScore: 2, awayScore: 1 }),
    match({ id: 'old-2', home: 'C', away: 'D' }),
  ];
  const generated = [
    match({ id: 'fresh-1', home: 'A', away: 'B' }),
    match({ id: 'fresh-2', home: 'C', away: 'D' }),
    match({ id: 'fresh-3', home: 'E', away: 'F' }),
  ];

  assertThrows(
    () => planFixtureRegeneration({ existing, generated }),
    'any existing match already played -> regeneration blocked (played fixture cannot be deleted or structurally replaced)',
  );
}

// exception reports the exact count of played matches
{
  const existing = [
    match({ id: 'old-1', home: 'A', away: 'B', status: 'completed', homeScore: 1, awayScore: 0 }),
    match({ id: 'old-2', home: 'C', away: 'D', status: 'played', homeScore: 3, awayScore: 3 }),
    match({ id: 'old-3', home: 'E', away: 'F' }),
  ];

  let caught: unknown = null;
  try {
    planFixtureRegeneration({ existing, generated: [] });
  } catch (e) {
    caught = e;
  }
  const isBlockedError = caught instanceof FixtureRegenerationBlockedError;
  assertEqual(isBlockedError, true, 'blocked error is a FixtureRegenerationBlockedError');
  if (isBlockedError) {
    assertEqual((caught as FixtureRegenerationBlockedError).playedMatchCount, 2, 'exception reports the exact count of played matches');
  }
}

// a match with a status but no score is NOT treated as played
{
  const existing = [match({ id: 'old-1', home: 'A', away: 'B', status: 'played' })];
  const generated = [match({ id: 'fresh-1', home: 'A', away: 'B' })];

  const plan = planFixtureRegeneration({ existing, generated });
  assertEqual(plan.toWrite.length, 1, 'status alone (no scores) does not block regeneration');
  assertEqual(plan.toWrite[0].id, 'old-1', 'status alone (no scores) -> existing id still reused');
  assertEqual(plan.idsToDelete, [], 'status alone (no scores) -> nothing pruned');
}

// generating twice in a row with identical pairings is stable (no duplicate logical fixtures)
{
  const existing = [match({ id: 'old-1', home: 'A', away: 'B', round: 1 }), match({ id: 'old-2', home: 'B', away: 'A', round: 2 })];
  const generated = [match({ id: 'fresh-1', home: 'A', away: 'B', round: 1 }), match({ id: 'fresh-2', home: 'B', away: 'A', round: 2 })];

  const plan = planFixtureRegeneration({ existing, generated });
  assertEqual(plan.idsToDelete, [], 'repeated generation: nothing to delete');
  assertEqual(
    new Set(plan.toWrite.map((m) => m.id)),
    new Set(['old-1', 'old-2']),
    'repeated generation with identical pairings produces no duplicate logical fixtures',
  );

  // Running the exact same plan a second time (simulating clicking
  // "Generate" again) must converge on the same ids once more.
  const plan2 = planFixtureRegeneration({ existing, generated });
  assertEqual(
    new Set(plan2.toWrite.map((m) => m.id)),
    new Set(['old-1', 'old-2']),
    'planning a third time from the same existing state is stable',
  );
}

// home/away legs stay distinguishable (A-vs-B round 1 != B-vs-A round 2)
{
  const existing = [match({ id: 'leg-1', home: 'A', away: 'B', round: 1 }), match({ id: 'leg-2', home: 'B', away: 'A', round: 2 })];
  const generated = [match({ id: 'gen-1', home: 'A', away: 'B', round: 1 }), match({ id: 'gen-2', home: 'B', away: 'A', round: 2 })];

  const plan = planFixtureRegeneration({ existing, generated });
  const firstLeg = plan.toWrite.find((m) => m.roundNumber === 1)!;
  const secondLeg = plan.toWrite.find((m) => m.roundNumber === 2)!;
  assertEqual(firstLeg.id, 'leg-1', 'leg 1 keeps its own id');
  assertEqual(secondLeg.id, 'leg-2', 'leg 2 keeps its own id');
  assertEqual(firstLeg.homeTeamId, 'A', 'leg 1 home team unchanged');
  assertEqual(secondLeg.homeTeamId, 'B', 'leg 2 home team unchanged');
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll fixtureRegenerationPlanner assertions passed.');
}
