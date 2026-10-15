// web_client/lib/algorithms/replaceParticipantPlanner.ts
//
// Safe participant replacement. Pure, Firebase-free decision logic -- TS
// mirror of lib/features/leagues/logic/replace_participant_planner.dart
// (see that file's own comment for the full rationale).
// lib/leagues/replaceParticipantRepository.ts is the only caller.
//
// Eligibility gate (applies uniformly across every format): the
// replacement team must have ZERO existing appearances anywhere in this
// competition (no FixtureMatch and no KnockoutMatch already references it
// as home or away). See the Dart file's comment for why this single rule
// makes every format-specific worry (Swiss duplicate opponents, knockout
// bracket integrity, round-robin schedule validity) a non-issue.

import { FixtureMatch, KnockoutMatch } from '@/lib/models/leagueDetails';
import { isMatchPlayed } from './fixtureRegenerationGuard';
import { isMatchFinished } from './tournamentController';

export class ReplaceParticipantBlockedError extends Error {
  constructor(reason: string) {
    super(reason);
  }
}

export interface ReplaceParticipantPreview {
  /** Matches already played/finished involving the old team. Never touched. */
  completedMatchCount: number;
  /** Fixture (non-knockout) matches to update: same id, only the team-id field changes. */
  fixtureMatchesToUpdate: FixtureMatch[];
  /** Knockout matches to update: same id, bracket wiring untouched. */
  knockoutMatchesToUpdate: KnockoutMatch[];
  /** Always 0 -- no completed/finished match is ever included above. */
  completedMatchesAffectedCount: number;
}

function involves(m: Pick<FixtureMatch, 'homeTeamId' | 'awayTeamId'>, teamId: string): boolean {
  return m.homeTeamId === teamId || m.awayTeamId === teamId;
}

function involvesKo(m: Pick<KnockoutMatch, 'homeTeamId' | 'awayTeamId'>, teamId: string): boolean {
  return m.homeTeamId === teamId || m.awayTeamId === teamId;
}

/**
 * Plans replacing `oldTeamId` with `newTeamId` across every existing
 * fixture/knockout match in the competition.
 *
 * Throws ReplaceParticipantBlockedError if:
 * - `newTeamId` already appears anywhere in `existingFixtureMatches` or
 *   `existingKnockoutMatches`, or
 * - `oldTeamId` and `newTeamId` are the same, or
 * - an unfinished Play-off leg's sibling leg has already been decided.
 */
export function planReplaceParticipant({
  oldTeamId,
  newTeamId,
  existingFixtureMatches,
  existingKnockoutMatches,
}: {
  oldTeamId: string;
  newTeamId: string;
  existingFixtureMatches: FixtureMatch[];
  existingKnockoutMatches: KnockoutMatch[];
}): ReplaceParticipantPreview {
  const oldId = oldTeamId.trim();
  const newId = newTeamId.trim();

  if (oldId === newId) {
    throw new ReplaceParticipantBlockedError(
      'The replacement must be a different team from the one being replaced.',
    );
  }

  const newAlreadyPlaying =
    existingFixtureMatches.some((m) => involves(m, newId)) ||
    existingKnockoutMatches.some((m) => involvesKo(m, newId));
  if (newAlreadyPlaying) {
    throw new ReplaceParticipantBlockedError(
      "The replacement team already has its own fixtures in this competition. " +
        'Choose a team with no existing matches, or create a new one.',
    );
  }

  const completedFixtures = existingFixtureMatches.filter((m) => involves(m, oldId) && isMatchPlayed(m)).length;
  const completedKnockouts = existingKnockoutMatches.filter(
    (m) => involvesKo(m, oldId) && isMatchFinished(m),
  ).length;

  const fixtureMatchesToUpdate = existingFixtureMatches
    .filter((m) => involves(m, oldId) && !isMatchPlayed(m))
    .map((m) => (m.homeTeamId === oldId ? { ...m, homeTeamId: newId } : { ...m, awayTeamId: newId }));

  const knockoutMatchesToUpdate: KnockoutMatch[] = [];
  for (const m of existingKnockoutMatches) {
    if (!involvesKo(m, oldId) || isMatchFinished(m)) continue;

    if (m.roundName === 'Play-off' && m.nextMatchId != null) {
      const sibling = existingKnockoutMatches.filter(
        (other) => other.roundName === 'Play-off' && other.nextMatchId === m.nextMatchId && other.isSecondLeg !== m.isSecondLeg,
      );
      if (sibling.some((s) => isMatchFinished(s))) {
        throw new ReplaceParticipantBlockedError(
          `Match ${m.id} is one leg of a two-legged Play-off tie whose other leg has already been played. ` +
            'Replacing a team mid-tie would break the aggregate result -- this replacement is rejected.',
        );
      }
    }

    knockoutMatchesToUpdate.push(m.homeTeamId === oldId ? { ...m, homeTeamId: newId } : { ...m, awayTeamId: newId });
  }

  return {
    completedMatchCount: completedFixtures + completedKnockouts,
    fixtureMatchesToUpdate,
    knockoutMatchesToUpdate,
    completedMatchesAffectedCount: 0,
  };
}
