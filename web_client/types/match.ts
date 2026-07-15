export type MatchStatus = 'scheduled' | 'pendingProof' | 'underReview' | 'played' | 'completed';

export interface FixtureMatch {
  isPlayed?: boolean;
  id: string;
  leagueId: string;
  groupId?: string;
  roundNumber: number;
  homeTeamId: string;
  awayTeamId: string;
  homeScore?: number;
  awayScore?: number;
  status: MatchStatus;
  sortIndex: number;
  updatedAtMs: number;
  version: number;
}

export interface KnockoutMatch {
  id: string;
  leagueId: string;
  roundName: string;
  homeTeamId?: string;
  awayTeamId?: string;
  homeScore?: number;
  awayScore?: number;
  homePenaltyScore?: number;
  awayPenaltyScore?: number;
  status: MatchStatus;
  nextMatchId?: string;
  isSecondLeg: boolean;
  loserGoesToMatchId?: string;
  winnerTeamId?: string; // Set after match completes
}
