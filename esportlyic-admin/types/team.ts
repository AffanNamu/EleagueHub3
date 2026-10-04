// types/team.ts
//
// Sourced from lib/features/leagues/models/team.dart and membership.dart,
// cross-checked against firestore.rules (leagues/{leagueId}/teams,
// leagues/{leagueId}/memberships). A team's roster is NOT an array on
// the team doc -- it's every membership whose teamId points at this
// team (role 1 = member; role 0 = the league's organizer, who is never
// on a roster).

// Mirrors Team.participantType*/claimStatus* static consts in
// lib/features/leagues/models/team.dart.
export type TeamParticipantType = 'registered' | 'external';
export type TeamClaimStatus = 'not_claimed' | 'claim_pending' | 'claimed' | 'revoked' | 'expired';

export interface LeagueTeam {
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
  /** Absent on every pre-existing team doc -- treat as 'registered'. */
  participantType?: TeamParticipantType;
  /** Only meaningful when participantType === 'external'. */
  claimStatus?: TeamClaimStatus;
  claimedAtMs?: number;
  createdByUserId?: string;
  updatedAtMs: number;
}

export interface LeagueMembership {
  membershipId: string;
  leagueId: string;
  userId: string;
  teamId: string | null;
  role: number;
  updatedAtMs: number;
}

export interface RosterMember {
  membershipId: string;
  userId: string;
  displayName: string;
  photoUrl: string;
}

export interface TeamWithRoster extends LeagueTeam {
  roster: RosterMember[];
}

// Mirrors the team_claims/{token} doc shape written by
// _generateTeamClaim/_confirmTeamClaim/_revokeTeamClaim in
// worker/src/index.js. Rules deny all client access to this collection --
// adminDb (Admin SDK) is the only way to read it, same as every other
// repository in this file reads leagues/teams/memberships.
export type TeamClaimDocStatus = 'pending' | 'claimed' | 'revoked';

export interface TeamClaim {
  token: string;
  leagueId: string;
  teamId: string;
  status: TeamClaimDocStatus;
  createdAtMs: number;
  createdByUserId: string;
  expiresAtMs: number;
  consumedAtMs: number | null;
  consumedByUserId: string | null;
  /** Resolved display name for consumedByUserId, when claimed. */
  consumedByDisplayName?: string;
}
