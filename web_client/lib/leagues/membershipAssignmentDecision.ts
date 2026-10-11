// lib/leagues/membershipAssignmentDecision.ts
//
// Pure decision logic for "assign an existing league member onto an
// existing team's roster" (Phase B of the participant/team-assignment
// initiative). Mirrors
// lib/features/leagues/logic/membership_assignment_decision.dart exactly
// -- same business rules, so Admin, Web and Flutter never disagree about
// when an assignment is allowed. Kept free of any Firestore dependency
// so the rules are testable in isolation (see
// membershipAssignmentDecision.test.ts).

export type MembershipAssignmentOutcome =
  | 'assign'
  | 'noopAlreadyOnTeam'
  | 'blockedTeamMissing'
  | 'blockedAlreadyOnDifferentTeam';

export function decideMembershipAssignment({
  targetTeamExists,
  membershipExists,
  currentTeamId,
  targetTeamId,
}: {
  targetTeamExists: boolean;
  membershipExists: boolean;
  currentTeamId: string;
  targetTeamId: string;
}): MembershipAssignmentOutcome {
  if (!targetTeamExists) return 'blockedTeamMissing';
  if (!membershipExists) return 'assign';

  const current = currentTeamId.trim();
  if (current === targetTeamId.trim()) return 'noopAlreadyOnTeam';
  if (current) return 'blockedAlreadyOnDifferentTeam';

  return 'assign';
}
