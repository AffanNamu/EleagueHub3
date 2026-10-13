// web_client/lib/algorithms/fixtureRegenerationGuard.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/algorithms/fixtureRegenerationGuard.test.ts`.
// PHASE C: web's "Generate Fixtures" flow had no protection at all
// against overwriting an in-progress competition's results; this is the
// TS port of fixture_regeneration_planner.dart's core rule.

import { assertFixtureRegenerationAllowed, FixtureRegenerationBlockedError, isMatchPlayed } from './fixtureRegenerationGuard';

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

function assertDoesNotThrow(fn: () => void, label: string) {
  try {
    fn();
    console.log(`ok - ${label}`);
  } catch (e) {
    failures++;
    console.error(`FAIL: ${label}\n  expected no throw, got: ${e instanceof Error ? e.message : String(e)}`);
  }
}

// isMatchPlayed
assertEqual(isMatchPlayed({ status: 'completed', homeScore: 2, awayScore: 1 }), true, 'isMatchPlayed: completed + both scores -> played');
assertEqual(isMatchPlayed({ status: 'played', homeScore: 0, awayScore: 0 }), true, 'isMatchPlayed: played + both scores -> played');
assertEqual(isMatchPlayed({ status: 'played' }), false, 'isMatchPlayed: status alone (no scores) -> NOT played');
assertEqual(isMatchPlayed({ status: 'scheduled', homeScore: 1, awayScore: 1 }), false, 'isMatchPlayed: scheduled status -> NOT played even with scores');
assertEqual(isMatchPlayed({}), false, 'isMatchPlayed: empty match -> NOT played');

// assertFixtureRegenerationAllowed
assertDoesNotThrow(
  () => assertFixtureRegenerationAllowed([]),
  'assertFixtureRegenerationAllowed: empty league -> allowed',
);
assertDoesNotThrow(
  () => assertFixtureRegenerationAllowed([{ status: 'scheduled' }, { status: 'scheduled' }]),
  'assertFixtureRegenerationAllowed: nothing played yet -> allowed',
);
assertThrows(
  () => assertFixtureRegenerationAllowed([{ status: 'completed', homeScore: 2, awayScore: 1 }]),
  'assertFixtureRegenerationAllowed: one played match -> blocked',
);

{
  let caught: unknown = null;
  try {
    assertFixtureRegenerationAllowed([
      { status: 'completed', homeScore: 2, awayScore: 1 },
      { status: 'played', homeScore: 0, awayScore: 0 },
      { status: 'scheduled' },
    ]);
  } catch (e) {
    caught = e;
  }
  const isBlockedError = caught instanceof FixtureRegenerationBlockedError;
  assertEqual(isBlockedError, true, 'blocked error is a FixtureRegenerationBlockedError');
  if (isBlockedError) {
    assertEqual((caught as FixtureRegenerationBlockedError).playedMatchCount, 2, 'exception reports the exact count of played matches');
  }
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll fixtureRegenerationGuard assertions passed.');
}
