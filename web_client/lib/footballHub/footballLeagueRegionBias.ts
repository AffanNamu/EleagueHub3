// web_client/lib/footballHub/footballLeagueRegionBias.ts
//
// Zero-permission "surface European competitions first" bias for the
// Football Hub's Matches tab -- TS mirror of
// lib/features/football_hub/logic/football_league_region_bias.dart (see
// that file's own comment for the full rationale). API-Football's
// /fixtures?date= endpoint returns every fixture happening worldwide on
// a given day with no regional ordering at all -- grouping by league (as
// the Matches tab already does) can put an obscure competition from
// anywhere in the world ahead of the Premier League or Bundesliga purely
// by API response order. This reorders those league groups -- it never
// drops one.
//
// Uses the SAME viewer-locale signal as
// lib/leagues/regionLocaleDetector.ts (browser navigator.language,
// never the Geolocation API, never a permission prompt) to decide
// whether to apply the bias at all; the bias itself classifies each
// FIXTURE's league by its API-Football `leagueCountry` name (e.g.
// "England", "Spain", "World" for UEFA club competitions), a completely
// different signal from the viewer's own locale.

import { isEuropeanViewer } from '@/lib/leagues/regionLocaleDetector';
import { FootballFixture } from './types';

/** Country names as API-Football represents them for UEFA's 55 member
 *  associations (the governing body for Europe's national leagues) --
 *  a soft relevance list, not a strict geography one, which is why a few
 *  transcontinental UEFA members (Russia, Turkey, Kazakhstan, Armenia,
 *  Azerbaijan, Georgia, Israel) are included alongside the mainland
 *  European countries. Kept in sync by hand with the Dart port's own
 *  _europeanCountryNames (no shared code module between the two apps). */
const EUROPEAN_COUNTRY_NAMES = new Set([
  'England', 'Scotland', 'Wales', 'Northern Ireland', 'Northern-Ireland',
  'Ireland', 'Republic of Ireland', 'Spain', 'Italy', 'Germany', 'France',
  'Portugal', 'Netherlands', 'Belgium', 'Switzerland', 'Austria', 'Poland',
  'Turkey', 'Russia', 'Ukraine', 'Greece', 'Sweden', 'Norway', 'Denmark',
  'Finland', 'Iceland', 'Croatia', 'Serbia', 'Bosnia', 'Bosnia and Herzegovina',
  'Slovenia', 'Slovakia', 'Czech Republic', 'Czechia', 'Hungary', 'Romania',
  'Bulgaria', 'Albania', 'North Macedonia', 'Macedonia', 'Montenegro',
  'Kosovo', 'Moldova', 'Belarus', 'Lithuania', 'Latvia', 'Estonia',
  'Cyprus', 'Malta', 'Luxembourg', 'Andorra', 'Monaco', 'San Marino',
  'Liechtenstein', 'Vatican', 'Georgia', 'Armenia', 'Azerbaijan',
  'Kazakhstan', 'Israel',
]);

/** UEFA club competitions API-Football files under country "World"
 *  rather than any single nation -- these are the well-known, stable
 *  API-Football league ids for them. */
const UEFA_INTERNATIONAL_LEAGUE_IDS = new Set([
  2, // UEFA Champions League
  3, // UEFA Europa League
  848, // UEFA Europa Conference League
]);

/** Whether a fixture's league should be treated as European for sorting
 *  purposes, by its country name or (for UEFA club competitions filed
 *  under "World") its league id. */
export function isEuropeanLeague({ country, leagueId }: { country: string; leagueId: number }): boolean {
  if (UEFA_INTERNATIONAL_LEAGUE_IDS.has(leagueId)) return true;
  return EUROPEAN_COUNTRY_NAMES.has(country.trim());
}

/** Stable-sorts `groups` (each an array of fixtures sharing one league,
 *  as the Matches tab already builds them) so that, when the current
 *  browser's locale is European, groups classified as European by
 *  isEuropeanLeague move ahead of every other group -- relative order is
 *  otherwise preserved exactly (a pure reorder, never a filter: every
 *  group passed in is still present in the result). When the browser's
 *  locale is not European, returns `groups` completely unchanged. */
export function sortLeagueGroupsForViewer(groups: FootballFixture[][]): FootballFixture[][] {
  if (!isEuropeanViewer()) return groups;

  const european: FootballFixture[][] = [];
  const rest: FootballFixture[][] = [];
  for (const group of groups) {
    const first = group[0];
    const country = first?.leagueCountry ?? '';
    const leagueId = first?.leagueId ?? -1;
    if (isEuropeanLeague({ country, leagueId })) {
      european.push(group);
    } else {
      rest.push(group);
    }
  }
  return [...european, ...rest];
}
