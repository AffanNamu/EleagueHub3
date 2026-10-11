// lib/features/leagues/logic/membership_assignment_decision.dart
//
// Pure decision logic for "assign an existing league member onto an
// existing team's roster" (Phase B of the participant/team-assignment
// initiative) -- kept free of any Firestore dependency so the business
// rules are unit-testable without a fake/live database.
//
// LocalLeaguesRepository.assignTeamToUserInLeague() is the only caller:
// it fetches the target team doc and the member's current membership
// doc, asks this decision function what to do, and then only ever
// performs exactly what it says.

enum MembershipAssignmentOutcome {
  /// Write the membership's teamId to the target team (new membership or
  /// updating an existing unassigned one).
  assign,

  /// Member is already on the target team -- treat as a successful,
  /// idempotent no-op. Calling this operation twice must never fail or
  /// create a duplicate.
  noopAlreadyOnTeam,

  /// The target team doesn't exist in this league. Refuse.
  blockedTeamMissing,

  /// The member is already on a *different* team. Refuse rather than
  /// silently move them -- an explicit removal/reassignment is a
  /// separate, deliberate action, not a side effect of this one.
  blockedAlreadyOnDifferentTeam,
}

class MembershipAssignmentDecision {
  const MembershipAssignmentDecision._();

  static MembershipAssignmentOutcome decide({
    required bool targetTeamExists,
    required bool membershipExists,
    required String currentTeamId,
    required String targetTeamId,
  }) {
    if (!targetTeamExists) {
      return MembershipAssignmentOutcome.blockedTeamMissing;
    }

    if (!membershipExists) {
      return MembershipAssignmentOutcome.assign;
    }

    final current = currentTeamId.trim();
    if (current == targetTeamId.trim()) {
      return MembershipAssignmentOutcome.noopAlreadyOnTeam;
    }

    if (current.isNotEmpty) {
      return MembershipAssignmentOutcome.blockedAlreadyOnDifferentTeam;
    }

    return MembershipAssignmentOutcome.assign;
  }
}
