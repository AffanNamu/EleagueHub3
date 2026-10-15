// lib/features/leagues/logic/team_ownership_transfer_decision.dart
//
// Pure decision logic for "replace the person behind an existing team"
// (the individual-player case called out in the participant-replacement
// brief, distinct from team-level replacement). Fixtures reference a
// TEAM id, never a person directly -- so this never touches a single
// match, fixture, or standing. It only ever changes who a team's
// ownerId/membership points to.
//
// LocalLeaguesRepository.transferTeamOwnership() is the only caller: it
// fetches the team doc and the new owner's current membership doc, asks
// this decision function what to do, and then only ever performs exactly
// what it says.

enum TeamOwnershipTransferOutcome {
  /// Clear the old owner's membership (if any) and point the team's
  /// ownerId + the new owner's membership at each other.
  transfer,

  /// The team doesn't exist in this league. Refuse.
  blockedTeamMissing,

  /// The "new owner" is the current owner already -- nothing to do.
  noopSameOwner,

  /// The new owner already has a membership pointing at a team (this one
  /// or a different one). Refuse rather than silently move them --
  /// mirrors MembershipAssignmentDecision's own
  /// blockedAlreadyOnDifferentTeam rule.
  blockedNewOwnerAlreadyOnATeam,
}

class TeamOwnershipTransferDecision {
  const TeamOwnershipTransferDecision._();

  static TeamOwnershipTransferOutcome decide({
    required bool teamExists,
    required String currentOwnerId,
    required String newOwnerId,
    required bool newOwnerMembershipExists,
    required String newOwnerCurrentTeamId,
  }) {
    if (!teamExists) {
      return TeamOwnershipTransferOutcome.blockedTeamMissing;
    }

    final current = currentOwnerId.trim();
    final next = newOwnerId.trim();
    if (current == next) {
      return TeamOwnershipTransferOutcome.noopSameOwner;
    }

    if (newOwnerMembershipExists && newOwnerCurrentTeamId.trim().isNotEmpty) {
      return TeamOwnershipTransferOutcome.blockedNewOwnerAlreadyOnATeam;
    }

    return TeamOwnershipTransferOutcome.transfer;
  }
}
