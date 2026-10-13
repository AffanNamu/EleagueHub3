// web_client/lib/algorithms/fixtureRegenerationGuard.ts
//
// PHASE C: ports lib/features/leagues/logic/fixture_regeneration_planner.dart's
// core safety rule to web_client. Unlike the Dart side, web's "Generate
// Fixtures" flow (admin/teams/page.tsx, admin/fixtures/page.tsx) never
// deletes existing match documents -- it only ever writes new ones on
// top (a different bug: no duplicate/overwrite protection at all, rather
// than Dart's old "delete everything" one) -- but it had NO check at all
// for whether any existing match already has a saved result. Generating
// again with a changed team list could silently orphan or corrupt an
// in-progress competition's fixtures. This is the same "never touch
// history once anything is played" rule, applied before web's generate
// handlers run.

export interface MinimalMatch {
  status?: string | null;
  homeScore?: number | null;
  awayScore?: number | null;
}

export class FixtureRegenerationBlockedError extends Error {
  playedMatchCount: number;

  constructor(playedMatchCount: number) {
    super(
      `Fixtures can't be regenerated: ${playedMatchCount} match${playedMatchCount === 1 ? '' : 'es'} already ` +
        `have a saved result. Regeneration is only available before any match in this competition has been played.`,
    );
    this.playedMatchCount = playedMatchCount;
  }
}

/** Mirrors FixtureMatch.isPlayed's own contract: status alone isn't enough, both scores must be present too. */
export function isMatchPlayed(m: MinimalMatch): boolean {
  const status = m.status || '';
  return (status === 'played' || status === 'completed') && m.homeScore != null && m.awayScore != null;
}

/**
 * Throws FixtureRegenerationBlockedError if any match in
 * [existingMatches] already has a saved result. Callers must check this
 * BEFORE writing any newly-generated fixture -- a running competition's
 * history is never silently replaced.
 */
export function assertFixtureRegenerationAllowed(existingMatches: MinimalMatch[]): void {
  const playedCount = existingMatches.filter(isMatchPlayed).length;
  if (playedCount > 0) {
    throw new FixtureRegenerationBlockedError(playedCount);
  }
}
