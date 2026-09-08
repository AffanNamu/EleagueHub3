// types/match.ts
//
// Mirrors FixtureMatch and KnockoutMatch exactly, cross-checked against
// fixture_match.dart and knockout_match.dart, and MatchStatus cross-
// checked directly against enums.dart's real enum values.

export type MatchStatus = 'scheduled' | 'pendingProof' | 'underReview' | 'played' | 'completed' | string;

export interface FixtureMatch {
  id: string;
  leagueId: string;
  groupId: string | null;
  roundNumber: number;
  homeTeamId: string;
  awayTeamId: string;
  homeScore: number | null;
  awayScore: number | null;
  status: MatchStatus;
  sortIndex: number;
  updatedAtMs: number;
  version: number;
}

export interface KnockoutMatch {
  id: string;
  leagueId: string;
  roundName: string;
  homeTeamId: string | null;
  awayTeamId: string | null;
  homeScore: number | null;
  awayScore: number | null;
  status: MatchStatus;
  tiebreakWinnerTeamId: string | null;
  nextMatchId: string | null;
  loserGoesToMatchId: string | null;
  isSecondLeg: boolean;
}

export interface PointAdjustment {
  id: string;
  leagueId: string;
  teamId: string;
  type: 'ADDITION' | 'DEDUCTION';
  points: number;
  reason: string;
  adjustedBy: string;
  createdAtMs: number;
}

export interface LeagueTeamSummary {
  teamId: string;
  name: string;
}
