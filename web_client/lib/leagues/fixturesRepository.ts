// web_client/lib/leagues/fixturesRepository.ts
//
// Firestore I/O for leagues/{leagueId}/matches regeneration -- mirrors
// LocalLeaguesRepository.replaceMatches() on the Flutter side (see
// fixtureRegenerationPlanner.ts / fixture_regeneration_planner.dart for the
// full rationale). The three audited web fixture-generation call sites
// (admin/teams/page.tsx's handleGenerateFixtures/handleSpinWheelConfirm,
// admin/fixtures/page.tsx's handleAutoGenerate) all funnel through
// regenerateFixtures() instead of writing the freshly-generated array
// directly, so a legacy random-UUID production fixture is never left
// behind as a duplicate alongside a new deterministic-id one.

import { collection, doc, getDocs, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { FixtureMatch } from '@/lib/models/leagueDetails';
import { planFixtureRegeneration, FixtureRegenerationPlan } from '@/lib/algorithms/fixtureRegenerationPlanner';

export async function fetchExistingFixtures(leagueId: string): Promise<FixtureMatch[]> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'matches'));
  return snap.docs.map((d) => {
    const data = d.data() as Partial<FixtureMatch>;
    const id = (data.id && String(data.id).trim()) || d.id;
    return { ...data, id } as FixtureMatch;
  });
}

/**
 * Plans and applies a fixture regeneration against the CURRENT server state
 * of leagues/{leagueId}/matches -- re-reads fresh immediately before
 * planning, so a stale client-side `matches` array (e.g. from a lagging
 * listener) is never the sole guard. Throws FixtureRegenerationBlockedError
 * (surfaced by the planner) if any existing match already has a saved
 * result; nothing is written in that case. Returns the applied plan so
 * callers can report how many fixtures were written.
 */
export async function regenerateFixtures(leagueId: string, generated: FixtureMatch[]): Promise<FixtureRegenerationPlan> {
  const existing = await fetchExistingFixtures(leagueId);
  const plan = planFixtureRegeneration({ existing, generated });

  const col = collection(db, 'leagues', leagueId, 'matches');

  // Firestore batches are capped at 500 writes; chunk defensively (mirrors
  // knockoutRepository.ts's saveKnockoutMatches). Deletes first, same
  // ordering as replaceMatches() on the Flutter side.
  const chunkSize = 400;

  for (let i = 0; i < plan.idsToDelete.length; i += chunkSize) {
    const batch = writeBatch(db);
    for (const id of plan.idsToDelete.slice(i, i + chunkSize)) {
      batch.delete(doc(col, id));
    }
    await batch.commit();
  }

  for (let i = 0; i < plan.toWrite.length; i += chunkSize) {
    const batch = writeBatch(db);
    for (const m of plan.toWrite.slice(i, i + chunkSize)) {
      batch.set(doc(col, m.id), m, { merge: true });
    }
    await batch.commit();
  }

  return plan;
}
