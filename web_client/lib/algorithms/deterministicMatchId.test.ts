// web_client/lib/algorithms/deterministicMatchId.test.ts
//
// No test runner configured in this app (see sessionOptions.test.ts) --
// same dependency-free convention: `npx tsx lib/algorithms/deterministicMatchId.test.ts`.
// PHASE C: mirrors test/deterministic_match_id_test.dart -- RoundRobinGenerator
// and SwissPairingEngine must produce the same match id every time they
// run with the same inputs, so a retry or re-run converges on the same
// Firestore documents instead of creating a second, independent set.

import { RoundRobinGenerator } from './roundRobin';
import { SwissPairingEngine } from './swissPairing';
import { Team } from '@/lib/models/leagueDetails';

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

function team(id: string): Team {
  return {
    id,
    leagueId: 'league1',
    name: id,
    ownerId: id,
    teamImageUrl: '',
    groupId: null,
    basePoints: 0,
    adminAdjustment: 0,
    finalPoints: 0,
    goalDifference: 0,
    goalsFor: 0,
    updatedAtMs: 0,
  };
}

// RoundRobinGenerator
{
  const first = RoundRobinGenerator.generate({ leagueId: 'league1', teamIds: ['A', 'B', 'C', 'D'], doubleRoundRobin: false, startRoundNumber: 1 });
  const second = RoundRobinGenerator.generate({ leagueId: 'league1', teamIds: ['A', 'B', 'C', 'D'], doubleRoundRobin: false, startRoundNumber: 1 });
  assertEqual(first.map((m) => m.id), second.map((m) => m.id), 'RoundRobinGenerator: regenerating with the same inputs produces identical ids');

  const ids = first.map((m) => m.id);
  assertEqual(new Set(ids).size, ids.length, 'RoundRobinGenerator: every match in a single-leg schedule has a unique id');
}

{
  const matches = RoundRobinGenerator.generate({ leagueId: 'league1', teamIds: ['A', 'B', 'C', 'D'], doubleRoundRobin: true, startRoundNumber: 1 });
  const ids = matches.map((m) => m.id);
  assertEqual(new Set(ids).size, ids.length, 'RoundRobinGenerator: double round-robin leg 2 ids never collide with leg 1 ids');
}

{
  const groupA = RoundRobinGenerator.generate({ leagueId: 'league1', teamIds: ['A', 'B'], doubleRoundRobin: false, groupId: 'Group A', startRoundNumber: 1 });
  const groupB = RoundRobinGenerator.generate({ leagueId: 'league1', teamIds: ['A', 'B'], doubleRoundRobin: false, groupId: 'Group B', startRoundNumber: 1 });
  assertEqual(groupA[0].id === groupB[0].id, false, 'RoundRobinGenerator: different groups with the same pairing/round do not collide');
}

// SwissPairingEngine
{
  const teams = Array.from({ length: 18 }, (_, i) => team(`t${i}`));
  const first = SwissPairingEngine.generateInitialRound({ leagueId: 'league1', teams, roundNumber: 1 });
  const second = SwissPairingEngine.generateInitialRound({ leagueId: 'league1', teams, roundNumber: 1 });
  assertEqual(first.map((m) => m.id), second.map((m) => m.id), 'SwissPairingEngine.generateInitialRound: same inputs produce identical ids');

  const ids = first.map((m) => m.id);
  assertEqual(new Set(ids).size, ids.length, 'SwissPairingEngine.generateInitialRound: ids are unique within the round');

  const round2First = SwissPairingEngine.generateNextRound({ leagueId: 'league1', teams, existingMatches: first as any, nextRoundNumber: 2 });
  const round2Second = SwissPairingEngine.generateNextRound({ leagueId: 'league1', teams, existingMatches: first as any, nextRoundNumber: 2 });
  assertEqual(round2First.map((m) => m.id), round2Second.map((m) => m.id), 'SwissPairingEngine.generateNextRound: same inputs produce identical ids');

  const round1Ids = new Set(first.map((m) => m.id));
  const round2Ids = new Set(round2First.map((m) => m.id));
  const overlap = [...round2Ids].filter((id) => round1Ids.has(id));
  assertEqual(overlap.length, 0, 'SwissPairingEngine: round 1 and round 2 ids never collide');
}

if (failures > 0) {
  console.error(`\n${failures} assertion(s) failed.`);
  process.exit(1);
} else {
  console.log('\nAll deterministicMatchId assertions passed.');
}
