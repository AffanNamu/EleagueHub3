export type MatchStatus = 'scheduled' | 'pendingProof' | 'underReview' | 'played' | 'completed';

// Mirrors Team.participantType*/claimStatus* static consts in
// lib/features/leagues/models/team.dart.
export type TeamParticipantType = 'registered' | 'external';
export type TeamClaimStatus = 'not_claimed' | 'claim_pending' | 'claimed' | 'revoked' | 'expired';

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
  /** Absent on every pre-existing team doc -- treat as 'registered'. */
  participantType?: TeamParticipantType;
  /** Only meaningful when participantType === 'external'. */
  claimStatus?: TeamClaimStatus;
  claimedAtMs?: number;
  createdByUserId?: string;
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
