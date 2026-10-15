// web_client/lib/algorithms/replaceParticipantPlanner.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/algorithms/replaceParticipantPlanner.test.ts`.
// Mirrors test/replace_participant_planner_test.dart scenario for scenario.

import { planReplaceParticipant, ReplaceParticipantBlockedError } from './replaceParticipantPlanner';
import { FixtureMatch, KnockoutMatch } from '@/lib/models/leagueDetails';

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

function assertTrue(actual: boolean, label: string) {
  assertEqual(actual, true, label);
}

function assertThrows(fn: () => void, label: string) {
  try {
    fn();
    failures++;
    console.error(`FAIL: ${label}\n  expected a throw, but none occurred`);
  } catch {
    console.log(`ok - ${label}`);
  }
}

function fm({
  id,
  home,
  away,
  round = 1,
  status = 'scheduled',
  homeScore = null,
  awayScore = null,
}: {
  id: string;
  home: string;
  away: string;
  round?: number;
  status?: FixtureMatch['status'];
  homeScore?: number | null;
  awayScore?: number | null;
}): FixtureMatch {
  return {
    id,
    leagueId: 'league1',
    groupId: null,
    roundNumber: round,
    homeTeamId: home,
    awayTeamId: away,
    homeScore,
    awayScore,
    status,
    sortIndex: 0,
    updatedAtMs: 0,
  };
}

function ko({
  id,
  roundName,
  home = null,
  away = null,
  status = 'scheduled',
  homeScore = null,
  awayScore = null,
  nextMatchId = null,
  isSecondLeg = false,
}: {
  id: string;
  roundName: string;
  home?: string | null;
  away?: string | null;
  status?: KnockoutMatch['status'];
  homeScore?: number | null;
  awayScore?: number | null;
  nextMatchId?: string | null;
  isSecondLeg?: boolean;
}): KnockoutMatch {
  return {
    id,
    leagueId: 'league1',
    roundName,
    homeTeamId: home,
    awayTeamId: away,
    homeScore,
    awayScore,
    status,
    tiebreakWinnerTeamId: null,
    nextMatchId,
    loserGoesToMatchId: null,
    isSecondLeg,
  };
}

// validation
assertThrows(
  () =>
    planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'A', existingFixtureMatches: [], existingKnockoutMatches: [] }),
  'replacement team must differ from the one being replaced',
);
{
  let caught: unknown = null;
  try {
    planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'A', existingFixtureMatches: [], existingKnockoutMatches: [] });
  } catch (e) {
    caught = e;
  }
  assertTrue(caught instanceof ReplaceParticipantBlockedError, 'blocked error has the right type');
}

assertThrows(
  () =>
    planReplaceParticipant({
      oldTeamId: 'A',
      newTeamId: 'NEW',
      existingFixtureMatches: [fm({ id: 'm1', home: 'A', away: 'B' }), fm({ id: 'm2', home: 'NEW', away: 'C' })],
      existingKnockoutMatches: [],
    }),
  'replacement team already playing its own fixtures is rejected',
);

assertThrows(
  () =>
    planReplaceParticipant({
      oldTeamId: 'A',
      newTeamId: 'NEW',
      existingFixtureMatches: [],
      existingKnockoutMatches: [ko({ id: 'k1', roundName: 'Quarter Finals', home: 'NEW', away: 'D' })],
    }),
  'replacement team already seeded in the knockout bracket is rejected',
);

// round-robin / fixtures
{
  const existing = [fm({ id: 'm1', home: 'A', away: 'B', round: 1 }), fm({ id: 'm2', home: 'C', away: 'A', round: 2 })];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: existing, existingKnockoutMatches: [] });

  assertEqual(preview.completedMatchCount, 0, 'completedMatchCount before any match played');
  assertEqual(preview.fixtureMatchesToUpdate.length, 2, 'both fixtures updated');
  assertEqual(preview.completedMatchesAffectedCount, 0, 'completedMatchesAffectedCount always 0');

  const m1 = preview.fixtureMatchesToUpdate.find((m) => m.id === 'm1')!;
  assertEqual(m1.homeTeamId, 'NEW', 'm1 home swapped');
  assertEqual(m1.awayTeamId, 'B', 'm1 away unchanged');

  const m2 = preview.fixtureMatchesToUpdate.find((m) => m.id === 'm2')!;
  assertEqual(m2.homeTeamId, 'C', 'm2 home unchanged');
  assertEqual(m2.awayTeamId, 'NEW', 'm2 away swapped');
}

{
  const existing = [
    fm({ id: 'm1', home: 'A', away: 'B', round: 1, status: 'completed', homeScore: 3, awayScore: 1 }),
    fm({ id: 'm2', home: 'A', away: 'C', round: 2 }),
  ];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: existing, existingKnockoutMatches: [] });

  assertEqual(preview.completedMatchCount, 1, 'one completed match counted');
  assertEqual(preview.fixtureMatchesToUpdate.length, 1, 'only the unplayed match is updated');
  assertEqual(preview.fixtureMatchesToUpdate[0].id, 'm2', 'updated match is m2');
  assertEqual(preview.fixtureMatchesToUpdate.some((m) => m.id === 'm1'), false, 'm1 never touched');
}

{
  const existing = [fm({ id: 'm1', home: 'A', away: 'B', round: 1 }), fm({ id: 'm2', home: 'C', away: 'D', round: 1 })];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: existing, existingKnockoutMatches: [] });
  assertEqual(preview.fixtureMatchesToUpdate.length, 1, 'unrelated fixture never included');
  assertEqual(preview.fixtureMatchesToUpdate[0].id, 'm1', 'only the related fixture is updated');
}

{
  const existing = [fm({ id: 'original-doc-id-123', home: 'A', away: 'B' })];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: existing, existingKnockoutMatches: [] });
  assertEqual(preview.fixtureMatchesToUpdate[0].id, 'original-doc-id-123', 'match id always preserved');
}

{
  const existing = [fm({ id: 'm1', home: 'A', away: 'B' })];
  const first = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: existing, existingKnockoutMatches: [] });
  const second = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: existing, existingKnockoutMatches: [] });
  assertEqual(first.fixtureMatchesToUpdate[0].id, second.fixtureMatchesToUpdate[0].id, 'retry-safe: same id');
  assertEqual(first.fixtureMatchesToUpdate[0].homeTeamId, second.fixtureMatchesToUpdate[0].homeTeamId, 'retry-safe: same result');
}

// knockout
{
  const koMatches = [ko({ id: 'qf1', roundName: 'Quarter Finals', home: 'A', away: 'D', nextMatchId: 'sf1' })];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: [], existingKnockoutMatches: koMatches });
  const updated = preview.knockoutMatchesToUpdate[0];
  assertEqual(updated.id, 'qf1', 'knockout match id preserved');
  assertEqual(updated.homeTeamId, 'NEW', 'knockout home swapped');
  assertEqual(updated.awayTeamId, 'D', 'knockout away unchanged');
  assertEqual(updated.nextMatchId, 'sf1', 'bracket wiring untouched');
}

{
  const koMatches = [ko({ id: 'qf1', roundName: 'Quarter Finals', home: 'A', away: 'D', status: 'completed', homeScore: 2, awayScore: 0 })];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: [], existingKnockoutMatches: koMatches });
  assertEqual(preview.completedMatchCount, 1, 'finished knockout match counted as completed');
  assertEqual(preview.knockoutMatchesToUpdate.length, 0, 'finished knockout match never updated');
}

assertThrows(
  () =>
    planReplaceParticipant({
      oldTeamId: 'A',
      newTeamId: 'NEW',
      existingFixtureMatches: [],
      existingKnockoutMatches: [
        ko({ id: 'po-leg1', roundName: 'Play-off', home: 'A', away: 'B', status: 'completed', homeScore: 2, awayScore: 1, nextMatchId: 'r16-1', isSecondLeg: false }),
        ko({ id: 'po-leg2', roundName: 'Play-off', home: 'B', away: 'A', nextMatchId: 'r16-1', isSecondLeg: true }),
      ],
    }),
  'Play-off leg whose sibling is already decided is rejected',
);

{
  const koMatches = [
    ko({ id: 'po-leg1', roundName: 'Play-off', home: 'A', away: 'B', nextMatchId: 'r16-1', isSecondLeg: false }),
    ko({ id: 'po-leg2', roundName: 'Play-off', home: 'B', away: 'A', nextMatchId: 'r16-1', isSecondLeg: true }),
  ];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: [], existingKnockoutMatches: koMatches });
  assertTrue(preview.knockoutMatchesToUpdate.some((m) => m.id === 'po-leg1'), 'Play-off leg with an unplayed sibling is allowed');
}

// mixed format
{
  const fixtures = [fm({ id: 'g1', home: 'A', away: 'B', round: 1 })];
  const koMatches = [ko({ id: 'qf1', roundName: 'Quarter Finals', home: 'A', away: 'D' })];
  const preview = planReplaceParticipant({ oldTeamId: 'A', newTeamId: 'NEW', existingFixtureMatches: fixtures, existingKnockoutMatches: koMatches });
  assertEqual(preview.fixtureMatchesToUpdate.length + preview.knockoutMatchesToUpdate.length, 2, 'mixed format: both collections updated in one plan');
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll replaceParticipantPlanner assertions passed.');
}
