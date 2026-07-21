// Direct TS port of lib/features/leagues/models/league_format.dart.
// Index mapping CONFIRMED against the real Dart file — do not reorder.
export type LeagueFormat = 'classic' | 'uclGroup' | 'uclSwiss' | 'worldCup';

const FORMAT_BY_INDEX: LeagueFormat[] = ['classic', 'uclGroup', 'uclSwiss', 'worldCup'];

export function leagueFormatFromInt(v: number): LeagueFormat {
  if (v < 0 || v >= FORMAT_BY_INDEX.length) return 'classic';
  return FORMAT_BY_INDEX[v];
}

export function leagueFormatIndex(f: LeagueFormat): number {
  return FORMAT_BY_INDEX.indexOf(f);
}

export function leagueFormatDisplayName(f: LeagueFormat): string {
  switch (f) {
    case 'classic':
      return 'Classic League';
    case 'uclGroup':
      return 'Group League';
    case 'uclSwiss':
      return 'Series League';
    case 'worldCup':
      return 'World Cup';
  }
}

export function leagueFormatIsWorldCup(f: LeagueFormat): boolean {
  return f === 'worldCup';
}
