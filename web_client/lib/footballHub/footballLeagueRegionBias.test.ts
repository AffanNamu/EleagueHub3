// web_client/lib/footballHub/footballLeagueRegionBias.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/footballHub/footballLeagueRegionBias.test.ts`.
// Mirrors test/football_league_region_bias_test.dart scenario for
// scenario. League ids used in fixtures deliberately avoid 2/3/848 (the
// real UEFA Champions/Europa/Conference League ids) except where a test
// is specifically exercising that special case -- a collision there
// caused the Dart test to fail on first write, so it's called out here
// to not repeat it.

import { isEuropeanLeague, sortLeagueGroupsForViewer } from './footballLeagueRegionBias';
import { FootballFixture } from './types';

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

function fixture({ leagueId, country, id = 1 }: { leagueId: number; country: string; id?: number }): FootballFixture {
  return {
    id,
    kickoff: new Date('2026-01-01'),
    statusShort: 'NS',
    statusLong: 'Not Started',
    elapsedMinutes: null,
    leagueId,
    leagueName: `League ${leagueId}`,
    leagueLogoUrl: '',
    leagueCountry: country,
    round: 'Regular Season - 1',
    season: 2026,
    homeTeamId: 1,
    homeTeamName: 'Home',
    homeTeamLogoUrl: '',
    awayTeamId: 2,
    awayTeamName: 'Away',
    awayTeamLogoUrl: '',
    homeGoals: null,
    awayGoals: null,
  };
}

// isEuropeanLeague
assertEqual(isEuropeanLeague({ country: 'England', leagueId: 39 }), true, 'recognized European country name: England');
assertEqual(isEuropeanLeague({ country: 'Spain', leagueId: 140 }), true, 'recognized European country name: Spain');
assertEqual(isEuropeanLeague({ country: 'Germany', leagueId: 78 }), true, 'recognized European country name: Germany');

assertEqual(isEuropeanLeague({ country: 'Brazil', leagueId: 71 }), false, 'non-European country name: Brazil');
assertEqual(isEuropeanLeague({ country: 'USA', leagueId: 253 }), false, 'non-European country name: USA');
assertEqual(isEuropeanLeague({ country: 'Japan', leagueId: 98 }), false, 'non-European country name: Japan');

assertEqual(isEuropeanLeague({ country: 'World', leagueId: 2 }), true, 'UEFA Champions League (country "World") is European by id');
assertEqual(isEuropeanLeague({ country: 'World', leagueId: 3 }), true, 'UEFA Europa League (country "World") is European by id');
assertEqual(isEuropeanLeague({ country: 'World', leagueId: 848 }), true, 'UEFA Conference League (country "World") is European by id');

assertEqual(isEuropeanLeague({ country: 'World', leagueId: 1 }), false, 'an unrelated "World" competition is not assumed European');

// sortLeagueGroupsForViewer -- navigator.language isn't settable under
// plain tsx/node, so these exercise the classification/grouping logic
// directly rather than the isEuropeanViewer() gate itself (already
// covered by regionLocaleDetector.test.ts).
function europeFirst(groups: FootballFixture[][]): FootballFixture[][] {
  const european = groups.filter((g) => isEuropeanLeague({ country: g[0].leagueCountry, leagueId: g[0].leagueId }));
  const rest = groups.filter((g) => !isEuropeanLeague({ country: g[0].leagueCountry, leagueId: g[0].leagueId }));
  return [...european, ...rest];
}

{
  const groups = [
    [fixture({ leagueId: 71, country: 'Brazil' })],
    [fixture({ leagueId: 39, country: 'England' })],
    [fixture({ leagueId: 98, country: 'Japan' })],
    [fixture({ leagueId: 140, country: 'Spain' })],
  ];
  const sorted = europeFirst(groups);
  assertEqual(
    sorted.map((g) => g[0].leagueId),
    [39, 140, 71, 98],
    'European leagues move to the front, relative order preserved within each group',
  );
  assertEqual(sorted.length, groups.length, 'every league group passed in is still present -- a reorder, never a filter');
}

{
  const groups = [
    [fixture({ leagueId: 71, country: 'Brazil' })],
    [fixture({ leagueId: 2, country: 'World' })], // Champions League
  ];
  const sorted = europeFirst(groups);
  assertEqual(sorted.map((g) => g[0].leagueId), [2, 71], 'a UEFA club competition under "World" still floats to the top');
}

// sortLeagueGroupsForViewer itself: under plain tsx/node (no real
// browser), navigator.language is never a European locale, so this must
// behave exactly like the non-European-viewer case -- every group
// present, completely unreordered -- never throw for lack of a browser.
{
  const groups = [
    [fixture({ leagueId: 71, country: 'Brazil' })],
    [fixture({ leagueId: 39, country: 'England' })],
  ];
  const result = sortLeagueGroupsForViewer(groups);
  assertEqual(result.map((g) => g[0].leagueId), [71, 39], 'sortLeagueGroupsForViewer is a no-op outside a European browser context');
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll footballLeagueRegionBias assertions passed.');
}
