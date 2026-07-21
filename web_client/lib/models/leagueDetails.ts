export type MatchStatus = 'scheduled' | 'playing' | 'completed' | 'played';

export interface Team {
  id: string;
  leagueId: string;
  name: string;
  ownerId: string;
  teamImageUrl: string;
  groupId: string | null;
  basePoints: number;
  adminAdjustment: number;
  finalPoints: number;
  goalDifference: number;
  goalsFor: number;
  updatedAtMs: number;
}

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

export interface LeagueAnnouncement {
  id: string;
  leagueId: string;
  masterLeagueId: string;
  scope: string;
  title: string;
  message: string;
  createdAtMs: number;
  authorId: string;
  authorName: string;
  pinned: boolean;
}
