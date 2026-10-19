// web_client/lib/leagues/regionLocaleDetector.ts
//
// Zero-permission "is this browser likely in Europe" signal -- TS mirror
// of lib/features/leagues/logic/region_locale_detector.dart (see that
// file's own comment for the full rationale). Used to surface
// Europe-relevant leagues first in the discovery list and to default a
// newly-created league's region. Deliberately NEVER touches the
// Geolocation API or any permission prompt -- it only reads the
// browser's own `navigator.language` (always available, no prompt),
// exactly the same class of signal already used for country-dependent
// behavior elsewhere in this app. A missing/unparseable region subtag is
// treated as "not Europe" (never assumed Europe by default), and nothing
// about this ever hides a league -- it only reorders them.

import { LeagueData } from '@/lib/models/league';

/** Human-readable region value stored on a league created by an
 *  organizer whose browser locale resolves to Europe. Leagues created
 *  before this feature (or by a non-European organizer) keep the
 *  pre-existing 'Global' default. */
export const EUROPE_REGION = 'Europe';

/** ISO 3166-1 alpha-2 codes for Europe -- identical set to the Dart
 *  port's _europeanCountryCodes, kept in sync by hand (no shared code
 *  module between the two apps). */
const EUROPEAN_COUNTRY_CODES = new Set([
  'AD', 'AL', 'AT', 'AX', 'BA', 'BE', 'BG', 'BY', 'CH', 'CY', 'CZ', 'DE',
  'DK', 'EE', 'ES', 'FI', 'FO', 'FR', 'GB', 'GG', 'GI', 'GR', 'HR', 'HU',
  'IE', 'IM', 'IS', 'IT', 'JE', 'LI', 'LT', 'LU', 'LV', 'MC', 'MD', 'ME',
  'MK', 'MT', 'NL', 'NO', 'PL', 'PT', 'RO', 'RS', 'RU', 'SE', 'SI', 'SJ',
  'SK', 'SM', 'TR', 'UA', 'VA', 'XK',
]);

/** Extracts the region/country subtag from a BCP-47 locale string like
 *  "en-GB", "fr-FR", or "de-DE-u-ca-gregory". Returns null if the tag has
 *  no region subtag (e.g. just "en"). */
function countryCodeFromLocaleString(localeString: string): string | null {
  const parts = localeString.split('-');
  if (parts.length < 2) return null;
  const candidate = parts[1];
  // A region subtag is exactly 2 letters (ISO 3166-1) or 3 digits (UN
  // M49) -- language-script tags like "zh-Hans" would otherwise be
  // mistaken for a region.
  if (/^[A-Za-z]{2}$/.test(candidate)) return candidate.toUpperCase();
  return null;
}

/** Whether `localeString`'s region subtag maps to a European country.
 *  Null/unrecognized input returns false -- a missing signal never
 *  defaults to "assume Europe". */
export function isEuropeanLocaleString(localeString: string | null | undefined): boolean {
  if (!localeString) return false;
  const code = countryCodeFromLocaleString(localeString);
  return code != null && EUROPEAN_COUNTRY_CODES.has(code);
}

/** Reads the browser's own locale (navigator.language) -- undefined in
 *  non-browser (SSR) contexts, where this always resolves to "not
 *  Europe" rather than throwing. */
function currentLocaleString(): string | null {
  if (typeof navigator === 'undefined') return null;
  return navigator.language ?? null;
}

/** Whether the CURRENT browser's locale resolves to Europe. */
export function isEuropeanViewer(): boolean {
  return isEuropeanLocaleString(currentLocaleString());
}

/** Default League.region value for a league being created right now in
 *  this browser. Preserves the pre-existing 'Global' default for
 *  everyone else. */
export function defaultRegionForCurrentLocale(): string {
  return isEuropeanViewer() ? EUROPE_REGION : 'Global';
}

/** Stable-sorts `leagues` so that, when the current browser's locale is
 *  European, leagues whose region is EUROPE_REGION are moved ahead of
 *  every other league -- relative order is otherwise preserved exactly
 *  (a pure reorder, never a filter: every league passed in is still
 *  present in the result). When the browser's locale is not European,
 *  returns `leagues` completely unchanged -- this is a per-viewer bias,
 *  not a global ranking change. */
export function sortLeaguesForViewer(leagues: LeagueData[]): LeagueData[] {
  if (!isEuropeanViewer()) return leagues;

  const european: LeagueData[] = [];
  const rest: LeagueData[] = [];
  for (const l of leagues) {
    if (l.region === EUROPE_REGION) {
      european.push(l);
    } else {
      rest.push(l);
    }
  }
  return [...european, ...rest];
}
