// web_client/lib/leagues/membershipAssignmentDecision.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/leagues/membershipAssignmentDecision.test.ts`.
// Mirrors test/membership_assignment_decision_test.dart's cases exactly.

import { decideMembershipAssignment } from './membershipAssignmentDecision';

let failures = 0;

function assertEqual<T>(actual: T, expected: T, label: string) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) {
    failures++;
    console.error(`FAIL: ${label}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
  } else {
    console.log(`ok - ${label}`);
  }
}

assertEqual(
  decideMembershipAssignment({
    targetTeamExists: true,
    membershipExists: true,
    currentTeamId: '',
    targetTeamId: 'team_mad_dog',
  }),
  'assign',
  'unassigned member, team exists -> assign',
);

assertEqual(
  decideMembershipAssignment({
    targetTeamExists: true,
    membershipExists: false,
    currentTeamId: '',
    targetTeamId: 'team_mad_dog',
  }),
  'assign',
  'no membership doc yet, team exists -> assign (creates membership)',
);

assertEqual(
  decideMembershipAssignment({
    targetTeamExists: false,
    membershipExists: true,
    currentTeamId: '',
    targetTeamId: 'deleted_team',
  }),
  'blockedTeamMissing',
  'target team does not exist -> blocked',
);

assertEqual(
  decideMembershipAssignment({
    targetTeamExists: true,
    membershipExists: true,
    currentTeamId: 'team_mad_dog',
    targetTeamId: 'team_mad_dog',
  }),
  'noopAlreadyOnTeam',
  'already on the target team -> idempotent no-op',
);

assertEqual(
  decideMembershipAssignment({
    targetTeamExists: true,
    membershipExists: true,
    currentTeamId: 'team_lira_palwo',
    targetTeamId: 'team_mad_dog',
  }),
  'blockedAlreadyOnDifferentTeam',
  'already on a DIFFERENT team -> blocked, never silently moved',
);

assertEqual(
  decideMembershipAssignment({
    targetTeamExists: true,
    membershipExists: true,
    currentTeamId: ' team_mad_dog ',
    targetTeamId: 'team_mad_dog',
  }),
  'noopAlreadyOnTeam',
  'whitespace in currentTeamId does not defeat the equality check',
);

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll membershipAssignmentDecision assertions passed.');
}
