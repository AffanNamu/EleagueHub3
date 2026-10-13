// web_client/lib/algorithms/fixtureRegenerationPlanner.ts
//
// TS port of lib/features/leagues/logic/fixture_regeneration_planner.dart --
// see that file's own comment for the full rationale. Pure, Firebase-free:
// the three audited web fixture-generation call sites (admin/teams/page.tsx's
// handleGenerateFixtures and handleSpinWheelConfirm, admin/fixtures/page.tsx's
// handleAutoGenerate) are the only callers -- each fetches the existing
// matches, asks this planner what to do, and then only ever executes exactly
// what the plan says.
//
// Unlike fixtureRegenerationGuard.ts (which only answers "is regeneration
// allowed at all"), this planner also decides WHICH fixtures to actually
// write: existing production fixtures may still carry legacy random-UUID
// document ids (from before deterministic ids shipped), and blindly writing
// the freshly-generated deterministic-id set would leave those legacy docs
// behind -- creating duplicate logical fixtures for the same pairing. This
// planner matches by logical identity, not by id, so a legacy id is always
// preserved for an unchanged pairing; a deterministic id is only ever used
// for a pairing that has no existing counterpart.

import { FixtureMatch } from '@/lib/models/leagueDetails';
import { FixtureRegenerationBlockedError, isMatchPlayed } from './fixtureRegenerationGuard';

export interface FixtureRegenerationPlan {
  /** Matches to upsert. A pairing that already existed (same home/away/round)
   *  carries the OLD document id forward instead of the fresh id the
   *  generator assigned it, so the match's identity is preserved across a
   *  regeneration. */
  toWrite: FixtureMatch[];
  /** Ids of existing documents that have no counterpart in the newly
   *  generated set (e.g. a team was removed, or the round structure
   *  changed) and should be deleted. */
  idsToDelete: string[];
}

/** Mirrors FixtureRegenerationPlanner._pairKey exactly -- same fields, same
 *  order, same separator -- so the two implementations agree on identity. */
function pairKey(m: Pick<FixtureMatch, 'homeTeamId' | 'awayTeamId' | 'roundNumber'>): string {
  return `${m.homeTeamId}|${m.awayTeamId}|${m.roundNumber}`;
}

/**
 * Plans a regeneration of `existing` into `generated`.
 *
 * Throws FixtureRegenerationBlockedError if any match in `existing` already
 * has a saved result (isMatchPlayed) -- a running competition's history is
 * never silently replaced, no matter how the caller got here.
 */
export function planFixtureRegeneration({
  existing,
  generated,
}: {
  existing: FixtureMatch[];
  generated: FixtureMatch[];
}): FixtureRegenerationPlan {
  const playedCount = existing.filter(isMatchPlayed).length;
  if (playedCount > 0) {
    throw new FixtureRegenerationBlockedError(playedCount);
  }

  const existingByPairKey = new Map<string, FixtureMatch>();
  for (const m of existing) {
    existingByPairKey.set(pairKey(m), m);
  }

  const usedExistingIds = new Set<string>();
  const toWrite: FixtureMatch[] = [];
  for (const m of generated) {
    const match = existingByPairKey.get(pairKey(m));
    if (match) {
      usedExistingIds.add(match.id);
      toWrite.push({ ...m, id: match.id });
    } else {
      toWrite.push(m);
    }
  }

  const idsToDelete = existing.filter((m) => !usedExistingIds.has(m.id)).map((m) => m.id);

  return { toWrite, idsToDelete };
}
