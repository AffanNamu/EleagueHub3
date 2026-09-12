export type MatchStatus = 'scheduled' | 'pendingProof' | 'underReview' | 'played' | 'completed';

export interface Team {
  id: string;
  leagueId: string;
  name: string;
  ownerId: string;
  teamImageUrl: string;
  logoUrl?: string;
  groupId: string | null;
  basePoints: number;
  adminAdjustment: number;
  finalPoints: number;
  goalDifference: number;
  goalsFor: number;
  goalsAgainst?: number;
  played?: number;
  won?: number;
  drawn?: number;
  lost?: number;
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
  isPlayed?: boolean;
  sortIndex: number;
  updatedAtMs: number;
  version?: number;
}

export interface KnockoutMatch {
  id: string;
  leagueId: string;
  roundName: string;
  homeTeamId: string | null;
  awayTeamId: string | null;
  homeScore: number | null;
  awayScore: number | null;
  homePenaltyScore?: number | null;
  awayPenaltyScore?: number | null;
  status: MatchStatus;
  tiebreakWinnerTeamId: string | null;
  nextMatchId: string | null;
  loserGoesToMatchId: string | null;
  isSecondLeg: boolean;
}

export interface LeagueSpace {
  leagueId: string;
  hostUserId: string;
  hostUid: string;
  title: string;
  isLive: boolean;
  startedAtMs?: number;
  endedAtMs?: number;
  updatedAtMs: number;
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
  pinnedAtMs?: number;
  pinnedBy?: string;
}
