// types/league.ts
//
// League (leagues/{id}) type for the admin Leagues module, matching
// league.dart and league_format.dart. Format is a persisted enum index —
// order must never change, ported exactly.

export const LEAGUE_FORMATS = ['classic', 'group', 'series', 'world_cup'] as const;
export type LeagueFormat = (typeof LEAGUE_FORMATS)[number];

export function leagueFormatFromIndex(index: number): LeagueFormat {
  return LEAGUE_FORMATS[index] ?? 'classic';
}

export function leagueFormatLabel(format: LeagueFormat): string {
  switch (format) {
    case 'classic':
      return 'Classic';
    case 'group':
      return 'Group Stage (UCL-style)';
    case 'series':
      return 'Series (Swiss)';
    case 'world_cup':
      return 'World Cup';
    default:
      return format;
  }
}

export interface League {
  id: string;
  name: string;
  format: LeagueFormat;
  organizerUid: string;
  ownerUid: string;
  masterLeagueId: string;
  isPrivate: boolean;
  maxTeams: number;
  memberCount: number;
  footballCategory: string;
  couponsEnabled: boolean;
  createdAtMs: number;
}
