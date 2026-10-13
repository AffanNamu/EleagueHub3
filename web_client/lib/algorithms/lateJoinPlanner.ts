// web_client/lib/algorithms/lateJoinPlanner.ts
//
// PHASE D: safe late-participant join. Pure, Firebase-free decision logic --
// TS mirror of lib/features/leagues/logic/late_join_planner.dart (see that
// file's own comment for the full rationale). lib/leagues/lateJoinRepository.ts
// is the only caller: it fetches the current league state, asks this planner
// what the operation would look like, and then only ever writes exactly
// what the plan says.
//
// Core rule (same one as every earlier phase): a running competition has
// HISTORY. Adding a late participant may change the FUTURE -- new fixtures
// against the newcomer -- but must NEVER touch an existing match, played or
// not. This planner only ever ADDS brand-new fixtures in brand-new round
// numbers; it never edits or deletes anything in `existingMatches`.
//
// Format support: only 'classic' (single round-robin table) has a safe,
// well-defined answer for "how do I insert one more team." See the Dart
// file's comment for why the other four formats (fixed group size, fixed
// Swiss field size, fixed knockout bracket size) don't.

import { FixtureMatch } from '@/lib/models/leagueDetails';
import { LeagueFormat, leagueFormatDisplayName } from '@/lib/models/leagueFormat';
import { RoundRobinGenerator } from './roundRobin';

export class LateJoinUnsupportedFormatError extends Error {
  format: LeagueFormat;

  constructor(format: LeagueFormat) {
    super(
      `Late joining is not supported for this league's format (${leagueFormatDisplayName(format)}) yet. ` +
        `It is currently only available for Classic League (single round-robin table), since every other ` +
        `format has a fixed structure (group size, Swiss field size, or bracket size) that a new participant ` +
        `would break.`,
    );
    this.format = format;
  }
}

export class LateJoinTeamAlreadyInLeagueError extends Error {
  constructor() {
    super('This team is already part of the league.');
  }
}

export interface LateJoinPreview {
  /** Existing matches that already have a saved result. Never touched. */
  completedMatchCount: number;
  /** Existing matches not yet played. Never touched either. */
  futureMatchCount: number;
  /** Brand-new fixtures this operation would create. */
  newFixtures: FixtureMatch[];
  /** Always 0 for a supported format. */
  existingMatchesAffectedCount: number;
}

function isMatchPlayed(m: Pick<FixtureMatch, 'status' | 'homeScore' | 'awayScore'>): boolean {
  return (m.status === 'played' || m.status === 'completed') && m.homeScore != null && m.awayScore != null;
}

export function supportsLateJoinFormat(format: LeagueFormat): boolean {
  return format === 'classic';
}

/**
 * Plans (but does not write) adding a new team to a Classic League.
 *
 * Throws LateJoinUnsupportedFormatError if `format` isn't supported, or
 * LateJoinTeamAlreadyInLeagueError if `newTeamId` is already in
 * `existingTeamIds`.
 *
 * New fixtures are appended in brand-new round numbers after the highest
 * existing round -- never interleaved into an existing round's pairing
 * structure. Home/away alternates across the newcomer's own fixtures.
 */
export function planLateJoin({
  format,
  leagueId,
  existingMatches,
  existingTeamIds,
  newTeamId,
  doubleRoundRobin,
}: {
  format: LeagueFormat;
  leagueId: string;
  existingMatches: FixtureMatch[];
  existingTeamIds: string[];
  newTeamId: string;
  doubleRoundRobin: boolean;
}): LateJoinPreview {
  if (!supportsLateJoinFormat(format)) {
    throw new LateJoinUnsupportedFormatError(format);
  }

  const trimmedNewId = newTeamId.trim();
  if (existingTeamIds.some((id) => id.trim() === trimmedNewId)) {
    throw new LateJoinTeamAlreadyInLeagueError();
  }

  const completedMatchCount = existingMatches.filter(isMatchPlayed).length;
  const futureMatchCount = existingMatches.length - completedMatchCount;

  let maxRound = 0;
  for (const m of existingMatches) {
    if (m.roundNumber > maxRound) maxRound = m.roundNumber;
  }

  const opponents = [...existingTeamIds].sort();
  const now = Date.now();

  const newFixtures: FixtureMatch[] = [];
  let round = maxRound;

  opponents.forEach((opponent, i) => {
    round += 1;
    const newcomerHome = i % 2 === 0;
    const homeId = newcomerHome ? trimmedNewId : opponent;
    const awayId = newcomerHome ? opponent : trimmedNewId;

    newFixtures.push({
      id: RoundRobinGenerator.matchId({ leagueId, roundNumber: round, homeTeamId: homeId, awayTeamId: awayId }),
      leagueId,
      groupId: null,
      roundNumber: round,
      homeTeamId: homeId,
      awayTeamId: awayId,
      homeScore: null,
      awayScore: null,
      status: 'scheduled',
      sortIndex: 0,
      updatedAtMs: now,
    });

    if (doubleRoundRobin) {
      round += 1;
      newFixtures.push({
        id: RoundRobinGenerator.matchId({ leagueId, roundNumber: round, homeTeamId: awayId, awayTeamId: homeId }),
        leagueId,
        groupId: null,
        roundNumber: round,
        homeTeamId: awayId,
        awayTeamId: homeId,
        homeScore: null,
        awayScore: null,
        status: 'scheduled',
        sortIndex: 0,
        updatedAtMs: now,
      });
    }
  });

  return {
    completedMatchCount,
    futureMatchCount,
    newFixtures,
    existingMatchesAffectedCount: 0,
  };
}
