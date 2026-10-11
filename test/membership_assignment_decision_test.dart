// test/membership_assignment_decision_test.dart
//
// Regression coverage for Phase B's "assign an unassigned league member
// onto an existing team" rules. See
// lib/features/leagues/logic/membership_assignment_decision.dart and
// LocalLeaguesRepository.assignTeamToUserInLeague().

import 'package:eleaguehub3/features/leagues/logic/membership_assignment_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MembershipAssignmentDecision.decide', () {
    test('unassigned member, team exists -> assign', () {
      final outcome = MembershipAssignmentDecision.decide(
        targetTeamExists: true,
        membershipExists: true,
        currentTeamId: '',
        targetTeamId: 'team_mad_dog',
      );
      expect(outcome, MembershipAssignmentOutcome.assign);
    });

    test('member has no membership doc yet, team exists -> assign (creates membership)', () {
      final outcome = MembershipAssignmentDecision.decide(
        targetTeamExists: true,
        membershipExists: false,
        currentTeamId: '',
        targetTeamId: 'team_mad_dog',
      );
      expect(outcome, MembershipAssignmentOutcome.assign);
    });

    test('target team does not exist -> blocked, regardless of membership state', () {
      final outcome = MembershipAssignmentDecision.decide(
        targetTeamExists: false,
        membershipExists: true,
        currentTeamId: '',
        targetTeamId: 'deleted_team',
      );
      expect(outcome, MembershipAssignmentOutcome.blockedTeamMissing);
    });

    test('member already on the target team -> idempotent no-op, not an error', () {
      final outcome = MembershipAssignmentDecision.decide(
        targetTeamExists: true,
        membershipExists: true,
        currentTeamId: 'team_mad_dog',
        targetTeamId: 'team_mad_dog',
      );
      expect(outcome, MembershipAssignmentOutcome.noopAlreadyOnTeam);
    });

    test('member already on a DIFFERENT team -> blocked, never silently moved', () {
      final outcome = MembershipAssignmentDecision.decide(
        targetTeamExists: true,
        membershipExists: true,
        currentTeamId: 'team_lira_palwo',
        targetTeamId: 'team_mad_dog',
      );
      expect(outcome, MembershipAssignmentOutcome.blockedAlreadyOnDifferentTeam);
    });

    test('calling assign twice in a row for the same target team is stable (assign then no-op)', () {
      // First call: membership exists but currentTeamId is still empty.
      final first = MembershipAssignmentDecision.decide(
        targetTeamExists: true,
        membershipExists: true,
        currentTeamId: '',
        targetTeamId: 'team_mad_dog',
      );
      expect(first, MembershipAssignmentOutcome.assign);

      // Second call: currentTeamId now reflects the first call's write.
      final second = MembershipAssignmentDecision.decide(
        targetTeamExists: true,
        membershipExists: true,
        currentTeamId: 'team_mad_dog',
        targetTeamId: 'team_mad_dog',
      );
      expect(second, MembershipAssignmentOutcome.noopAlreadyOnTeam);
    });

    test('whitespace in currentTeamId/targetTeamId does not defeat the equality check', () {
      final outcome = MembershipAssignmentDecision.decide(
        targetTeamExists: true,
        membershipExists: true,
        currentTeamId: ' team_mad_dog ',
        targetTeamId: 'team_mad_dog',
      );
      expect(outcome, MembershipAssignmentOutcome.noopAlreadyOnTeam);
    });
  });
}
