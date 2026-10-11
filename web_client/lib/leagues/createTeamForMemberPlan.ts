// web_client/lib/leagues/createTeamForMemberPlan.ts
//
// Pure planning step for createTeamForMemberWeb (leaguesRepository.ts) --
// kept in its own file, with no Firestore/firebase import at all, so it
// loads and is testable (createTeamForMember.test.ts) without
// initializing the Firebase app. Mirrors the same no-Firestore-dependency
// convention as membershipAssignmentDecision.ts and
// lib/features/leagues/logic/fixture_regeneration_planner.dart on the
// Dart side.

import { decideMembershipAssignment, MembershipAssignmentOutcome } from './membershipAssignmentDecision';

export interface TeamForMemberPlan {
  outcome: MembershipAssignmentOutcome;
  /** null when outcome is blockedAlreadyOnDifferentTeam -- the caller must throw and write nothing in that case. */
  teamWrite: Record<string, unknown> | null;
  /** null when the membership already correctly points at this team (noopAlreadyOnTeam) -- nothing more to write. */
  membershipWrite: { mode: 'create' | 'update'; data: Record<string, unknown> } | null;
}

/**
 * Decides what createTeamForMemberWeb's Firestore transaction should
 * write. Mirrors decideMembershipAssignment's contract exactly:
 * blockedAlreadyOnDifferentTeam must never produce a team write OR a
 * membership write, so a caller that bails out on seeing it (as
 * createTeamForMemberWeb does, throwing before calling tx.set at all)
 * can never leave a partially-applied state.
 */
export function planCreateTeamForMember({
  leagueId,
  teamId,
  membershipExists,
  currentTeamId,
  now,
  teamFields,
}: {
  leagueId: string;
  teamId: string;
  membershipExists: boolean;
  currentTeamId: string;
  now: number;
  teamFields: { name: string; ownerId: string; teamImageUrl: string; groupId?: string };
}): TeamForMemberPlan {
  const outcome = decideMembershipAssignment({
    targetTeamExists: true, // created in the same transaction this plan is applied in
    membershipExists,
    currentTeamId,
    targetTeamId: teamId,
  });

  if (outcome === 'blockedAlreadyOnDifferentTeam') {
    return { outcome, teamWrite: null, membershipWrite: null };
  }

  const teamWrite: Record<string, unknown> = {
    id: teamId,
    leagueId,
    name: teamFields.name,
    ownerId: teamFields.ownerId,
    teamImageUrl: teamFields.teamImageUrl,
    played: 0,
    won: 0,
    drawn: 0,
    lost: 0,
    goalsFor: 0,
    goalsAgainst: 0,
    goalDifference: 0,
    basePoints: 0,
    adminAdjustment: 0,
    finalPoints: 0,
    updatedAtMs: now,
  };
  if (teamFields.groupId) teamWrite.groupId = teamFields.groupId;

  if (outcome === 'noopAlreadyOnTeam') {
    return { outcome, teamWrite, membershipWrite: null };
  }

  const membershipWrite = membershipExists
    ? { mode: 'update' as const, data: { teamId, updatedAtMs: now } }
    : {
        mode: 'create' as const,
        data: { id: teamId, leagueId, userId: teamId, teamId, role: 1, updatedAtMs: now, version: 1 },
      };

  return { outcome, teamWrite, membershipWrite };
}
