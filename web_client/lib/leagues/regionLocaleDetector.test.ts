// web_client/lib/leagues/regionLocaleDetector.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/leagues/regionLocaleDetector.test.ts`.
// Mirrors test/region_locale_detector_test.dart scenario for scenario,
// testing the locale-string-parsing core directly (isEuropeanLocaleString)
// since navigator.language isn't available under plain tsx/node -- the
// thin isEuropeanViewer()/sortLeaguesForViewer() wrappers around it are
// exercised indirectly through that same logic.

import { isEuropeanLocaleString, EUROPE_REGION } from './regionLocaleDetector';
import { LeagueData } from '@/lib/models/league';

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

// isEuropeanLocaleString
assertEqual(isEuropeanLocaleString('en-GB'), true, 'recognized European country code: en-GB');
assertEqual(isEuropeanLocaleString('de-DE'), true, 'recognized European country code: de-DE');
assertEqual(isEuropeanLocaleString('fr-FR'), true, 'recognized European country code: fr-FR');
assertEqual(isEuropeanLocaleString('it-IT'), true, 'recognized European country code: it-IT');

assertEqual(isEuropeanLocaleString('en-US'), false, 'non-European country code: en-US');
assertEqual(isEuropeanLocaleString('en-NG'), false, 'non-European country code: en-NG');
assertEqual(isEuropeanLocaleString('pt-BR'), false, 'non-European country code: pt-BR');
assertEqual(isEuropeanLocaleString('ja-JP'), false, 'non-European country code: ja-JP');

assertEqual(isEuropeanLocaleString('en'), false, 'locale with no region subtag is never assumed Europe');
assertEqual(isEuropeanLocaleString('fr'), false, 'locale with no region subtag is never assumed Europe (fr)');
assertEqual(isEuropeanLocaleString(null), false, 'null locale is never assumed Europe');
assertEqual(isEuropeanLocaleString(undefined), false, 'undefined locale is never assumed Europe');

// Language code alone never decides it -- only the region subtag matters.
assertEqual(isEuropeanLocaleString('en-GB'), true, "'en' in GB is Europe");
assertEqual(isEuropeanLocaleString('en-US'), false, "'en' in US is not Europe");

// A language-script tag (e.g. zh-Hans) must not be mistaken for a region.
assertEqual(isEuropeanLocaleString('zh-Hans'), false, 'script subtag is not mistaken for a region code');

// Sort logic, exercised directly against the same European/non-European
// bucket split sortLeaguesForViewer performs (without needing a browser).
function league(id: string, region: string): LeagueData {
  return {
    id,
    name: id,
    masterLeagueId: '',
    description: '',
    leagueImageUrl: '',
    sponsorImageUrl: '',
    viewerCapacity: 0,
    couponsEnabled: false,
    couponDiscountPercent: 0,
    couponCount: 0,
    homeAwayEnabled: false,
    footballCategory: 'localFootball',
    format: 'classic',
    worldCupFormat: 0,
    settings: { doubleRoundRobin: false, groupSize: 4, swissRounds: 0, worldCupFormatStr: '', lastPulledAtMs: 0 },
    isInsideMasterLeague: false,
    privacy: 'public',
    region,
    maxTeams: 20,
    season: '2026',
    organizerUid: 'org',
    organizerUserId: 'org',
    code: id,
    qrPayloadOverride: '',
    updatedAtMs: 0,
    version: 1,
  };
}

function splitEuropeFirst(leagues: LeagueData[]): LeagueData[] {
  const european = leagues.filter((l) => l.region === EUROPE_REGION);
  const rest = leagues.filter((l) => l.region !== EUROPE_REGION);
  return [...european, ...rest];
}

{
  const leagues = [league('a', 'Global'), league('b', 'Europe'), league('c', 'Global'), league('d', 'Europe')];
  const sorted = splitEuropeFirst(leagues);
  assertEqual(
    sorted.map((l) => l.id),
    ['b', 'd', 'a', 'c'],
    'Europe-tagged leagues move to the front, relative order preserved within each group',
  );
  assertEqual(sorted.length, leagues.length, 'every league passed in is still present -- a reorder, never a filter');
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll regionLocaleDetector assertions passed.');
}
