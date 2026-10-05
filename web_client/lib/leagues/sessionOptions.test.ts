// web_client/lib/leagues/sessionOptions.test.ts
//
// web_client has no test runner configured (no jest/vitest in
// package.json) -- rather than take on a new test-framework dependency
// unasked, this is a small, dependency-free self-check: plain assertions,
// run directly with `npx tsx web_client/lib/leagues/sessionOptions.test.ts`
// (or `node` after a `tsc` build). Mirrors
// test/competition_session_options_test.dart's Dart test cases exactly,
// so both clients are verified against the same behavior.

import {
  generateSessionOptions,
  suggestedDefaultSession,
  normalizeCustomSession,
  SESSION_MAX_LENGTH,
} from './sessionOptions';

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

// -- generateSessionOptions --
assertEqual(
  generateSessionOptions(new Date(2026, 5, 1)),
  ['2026', '2027', '2028', '2026/2027', '2027/2028', '2028/2029'],
  'generateSessionOptions: 3 single years + 3 ranges anchored to 2026',
);
assertEqual(
  generateSessionOptions(new Date(2030, 11, 31))[0],
  '2030',
  'generateSessionOptions: advances with the clock, never a fixed year',
);

// -- suggestedDefaultSession --
assertEqual(
  suggestedDefaultSession(new Date(2026, 2, 1)),
  '2026/2027',
  'suggestedDefaultSession: current/next year range',
);
assertEqual(
  suggestedDefaultSession(new Date(2030, 2, 1)),
  '2030/2031',
  'suggestedDefaultSession: advances with the clock',
);

// -- normalizeCustomSession --
assertEqual(normalizeCustomSession('2026'), '2026', 'normalizeCustomSession: accepts a single year');
assertEqual(normalizeCustomSession('2027/2028'), '2027/2028', 'normalizeCustomSession: accepts a year range');
assertEqual(
  normalizeCustomSession('  Summer Cup 2027  '),
  'Summer Cup 2027',
  'normalizeCustomSession: trims whitespace',
);
assertEqual(normalizeCustomSession(''), null, 'normalizeCustomSession: rejects empty input');
assertEqual(normalizeCustomSession('   '), null, 'normalizeCustomSession: rejects whitespace-only input');
assertEqual(
  normalizeCustomSession('A'.repeat(SESSION_MAX_LENGTH + 1)),
  null,
  'normalizeCustomSession: rejects input beyond max length',
);
assertEqual(
  normalizeCustomSession('A'.repeat(SESSION_MAX_LENGTH)),
  'A'.repeat(SESSION_MAX_LENGTH),
  'normalizeCustomSession: accepts input right at max length',
);

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll sessionOptions assertions passed.');
}
