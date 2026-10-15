// test/team_ownership_transfer_decision_test.dart
//
// Regression coverage for the individual-player replacement case:
// changing who controls an existing team never touches a match, fixture,
// or standing -- it only ever changes Team.ownerId and a membership link.
// See lib/features/leagues/logic/team_ownership_transfer_decision.dart.

import 'package:eleaguehub3/features/leagues/logic/team_ownership_transfer_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TeamOwnershipTransferDecision.decide', () {
    test('missing team is blocked', () {
      final outcome = TeamOwnershipTransferDecision.decide(
        teamExists: false,
        currentOwnerId: 'old',
        newOwnerId: 'new',
        newOwnerMembershipExists: false,
        newOwnerCurrentTeamId: '',
      );
      expect(outcome, TeamOwnershipTransferOutcome.blockedTeamMissing);
    });

    test('transferring to the current owner is a no-op', () {
      final outcome = TeamOwnershipTransferDecision.decide(
        teamExists: true,
        currentOwnerId: 'same-uid',
        newOwnerId: 'same-uid',
        newOwnerMembershipExists: true,
        newOwnerCurrentTeamId: 'team1',
      );
      expect(outcome, TeamOwnershipTransferOutcome.noopSameOwner);
    });

    test('new owner already on a different team is blocked', () {
      final outcome = TeamOwnershipTransferDecision.decide(
        teamExists: true,
        currentOwnerId: 'old',
        newOwnerId: 'new',
        newOwnerMembershipExists: true,
        newOwnerCurrentTeamId: 'some-other-team',
      );
      expect(outcome, TeamOwnershipTransferOutcome.blockedNewOwnerAlreadyOnATeam);
    });

    test('new owner already assigned to THIS team is also blocked (nonsensical transfer)', () {
      final outcome = TeamOwnershipTransferDecision.decide(
        teamExists: true,
        currentOwnerId: 'old',
        newOwnerId: 'new',
        newOwnerMembershipExists: true,
        newOwnerCurrentTeamId: 'this-team',
      );
      expect(outcome, TeamOwnershipTransferOutcome.blockedNewOwnerAlreadyOnATeam);
    });

    test('new owner with no membership yet (unassigned) is allowed to transfer', () {
      final outcome = TeamOwnershipTransferDecision.decide(
        teamExists: true,
        currentOwnerId: 'old',
        newOwnerId: 'new',
        newOwnerMembershipExists: false,
        newOwnerCurrentTeamId: '',
      );
      expect(outcome, TeamOwnershipTransferOutcome.transfer);
    });

    test('new owner with an existing but team-less membership is allowed to transfer', () {
      final outcome = TeamOwnershipTransferDecision.decide(
        teamExists: true,
        currentOwnerId: 'old',
        newOwnerId: 'new',
        newOwnerMembershipExists: true,
        newOwnerCurrentTeamId: '',
      );
      expect(outcome, TeamOwnershipTransferOutcome.transfer);
    });

    test('a team with no current owner (external/unclaimed) can still be transferred', () {
      final outcome = TeamOwnershipTransferDecision.decide(
        teamExists: true,
        currentOwnerId: '',
        newOwnerId: 'new',
        newOwnerMembershipExists: false,
        newOwnerCurrentTeamId: '',
      );
      expect(outcome, TeamOwnershipTransferOutcome.transfer);
    });
  });
}
