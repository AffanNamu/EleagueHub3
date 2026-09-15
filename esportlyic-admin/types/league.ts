// types/league.ts
//
// League (leagues/{id}) type for the admin Leagues module, matching
// league.dart and league_format.dart. Format is a persisted enum index —
// order must never change, ported exactly.

export const LEAGUE_FORMATS = ['classic', 'group', 'series', 'world_cup', 'direct_knockout'] as const;
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
    case 'direct_knockout':
      return 'Direct Knockout';
    default:
      return format;
  }
}

export interface League {
  id: string;
  name: string;
  description: string;
  format: LeagueFormat;
  organizerUid: string;
  ownerUid: string;
  masterLeagueId: string;
  isPrivate: boolean;
  maxTeams: number;
  memberCount: number;
  footballCategory: string;
  couponsEnabled: boolean;
  region: string;
  season: string;
  leagueImageUrl: string;
  sponsorImageUrl: string;
  createdAtMs: number;
}

/**
 * Fields intentionally editable from the admin panel. format, maxTeams,
 * masterLeagueId, and ownership (organizerUid/ownerUid) are deliberately
 * excluded — changing them on a league that already has matches/teams/
 * a bracket risks breaking structural invariants those subsystems assume
 * (e.g. maxTeams shrinking below already-joined teams, or a format change
 * leaving knockout data that no longer matches the new format). Ownership
 * transfer is a separate, riskier feature not built here.
 */
export interface LeagueInput {
  name: string;
  description: string;
  isPrivate: boolean;
  region: string;
  season: string;
  leagueImageUrl: string;
  sponsorImageUrl: string;
}
