// types/team.ts
//
// Sourced from lib/features/leagues/models/team.dart and membership.dart,
// cross-checked against firestore.rules (leagues/{leagueId}/teams,
// leagues/{leagueId}/memberships). A team's roster is NOT an array on
// the team doc -- it's every membership whose teamId points at this
// team (role 1 = member; role 0 = the league's organizer, who is never
// on a roster).

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
