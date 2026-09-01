// lib/leagues/knockoutGeneration.ts
//
// Wires StandingsEngine (per-group / Swiss standings) into
// tournamentController's seeding functions, and replicates the validation
// checks from league_detail_screen.dart's _generateSwissKnockouts /
// _generateGroupKnockouts / _generateWorldCupKnockouts — team-count checks,
// "all group/round matches must be finished first", group-structure
// validation — so the web generate buttons refuse to seed a bracket from
// incomplete data exactly like Flutter does, rather than silently
// producing a broken/partial one.
//
// Throws a plain Error with a user-facing message on any failed check —
// callers (LeagueDetailScreenClient) catch and surface it, mirroring the
// _toastWarn/_toastErr calls in the Flutter screen.

import { Team } from '@/types/league';
import { FixtureMatch } from '@/types/match';
import { StandingsEngine } from '@/lib/algorithms/standingsEngine';
import {
  KnockoutMatch,
  StandingsRowLike,
  seedKnockoutsFromGroups,
  seedSwissKnockouts,
  seedWorldCupKnockouts32,
  seedWorldCupKnockouts48,
} from '@/lib/algorithms/tournamentController';

function toRows(teams: Team[]): StandingsRowLike[] {
  return teams.map((t) => ({
    teamId: t.id,
    finalPoints: t.finalPoints || 0,
    gd: t.goalDifference || 0,
    gf: t.goalsFor || 0,
  }));
}

function matchIsPlayed(m: FixtureMatch): boolean {
  return m.status === 'played' || m.status === 'completed' || m.isPlayed === true;
}

function groupIdOf(t: Team): string {
  return (t.groupId || '').trim();
}

export async function generateGroupKnockouts(leagueId: string, teams: Team[], matches: FixtureMatch[]): Promise<KnockoutMatch[]> {
  if (!(teams.length === 16 || teams.length === 32)) {
    throw new Error(`Group knockouts require 16 or 32 teams. Currently: ${teams.length}.`);
  }

  const groupMatches = matches.filter((m) => !!m.groupId);
  if (groupMatches.length === 0) throw new Error('No group matches found yet.');
  if (groupMatches.some((m) => !matchIsPlayed(m))) {
    throw new Error('Finish all group stage matches first before generating knockouts.');
  }

  const groupIds = Array.from(new Set(teams.map(groupIdOf).filter(Boolean))).sort();
  const expectedGroupCount = teams.length / 4;
  if (groupIds.length !== expectedGroupCount) {
    throw new Error(`Invalid group structure: expected ${expectedGroupCount} groups, found ${groupIds.length}.`);
  }

  const groupStandings: Record<string, StandingsRowLike[]> = {};
  for (const gid of groupIds) {
    const groupTeams = teams.filter((t) => groupIdOf(t) === gid);
    if (groupTeams.length !== 4) {
      throw new Error(`Group ${gid} has ${groupTeams.length} teams, expected 4.`);
    }
    const groupTeamIds = new Set(groupTeams.map((t) => t.id));
    const gm = groupMatches.filter((m) => groupTeamIds.has(m.homeTeamId) && groupTeamIds.has(m.awayTeamId));
    const computed = StandingsEngine.compute(groupTeams, gm, false);
    groupStandings[gid] = toRows(computed);
  }

  const result = seedKnockoutsFromGroups({ leagueId, groupStandings });
  if (result.length === 0) throw new Error('Failed to seed the group-stage knockout bracket.');
  return result;
}

export async function generateSwissKnockouts(
  leagueId: string,
  teams: Team[],
  matches: FixtureMatch[],
  swissRounds: number,
): Promise<KnockoutMatch[]> {
  const n = teams.length;
  if (!(n === 18 || n === 36)) {
    throw new Error(`Swiss knockouts require 18 or 36 teams. Currently: ${n}.`);
  }

  const swissMatches = matches.filter((m) => !m.groupId);
  const roundsPresent = new Set(swissMatches.map((m) => m.roundNumber));
  for (let r = 1; r <= swissRounds; r++) {
    if (!roundsPresent.has(r)) {
      throw new Error(`Generate all ${swissRounds} Swiss rounds first.`);
    }
  }

  const requiredMatches = swissMatches.filter((m) => m.roundNumber <= swissRounds);
  if (requiredMatches.some((m) => !matchIsPlayed(m))) {
    throw new Error(`Finish all ${swissRounds} Swiss rounds before generating knockouts.`);
  }

  const computed = StandingsEngine.compute(teams, swissMatches, false);
  if (computed.length !== teams.length) {
    throw new Error('Standings/team count mismatch.');
  }

  const result = seedSwissKnockouts({ leagueId, swissStandings: toRows(computed) });
  if (result.length === 0) throw new Error('Failed to seed the Swiss knockout bracket.');
  return result;
}

export async function generateWorldCupKnockouts(
  leagueId: string,
  teams: Team[],
  matches: FixtureMatch[],
  worldCupFormat: number, // 32 or 48
): Promise<KnockoutMatch[]> {
  if (teams.length !== worldCupFormat) {
    throw new Error(`Invalid team count for a ${worldCupFormat}-team World Cup: ${teams.length}.`);
  }

  const groupMatches = matches.filter((m) => !!m.groupId);
  if (groupMatches.length === 0) throw new Error('No World Cup group stage matches found yet.');
  if (groupMatches.some((m) => !matchIsPlayed(m))) {
    throw new Error('Finish all group stage matches first before generating knockouts.');
  }

  const groupIds = Array.from(new Set(teams.map(groupIdOf).filter(Boolean))).sort();
  const expectedGroupCount = worldCupFormat === 48 ? 12 : 8;
  if (groupIds.length !== expectedGroupCount) {
    throw new Error(`Invalid group structure: expected ${expectedGroupCount} groups, found ${groupIds.length}.`);
  }

  const groupStandings: Record<string, StandingsRowLike[]> = {};
  for (const gid of groupIds) {
    const groupTeams = teams.filter((t) => groupIdOf(t) === gid);
    if (groupTeams.length !== 4) {
      throw new Error(`Invalid group (${gid}): expected 4 teams, found ${groupTeams.length}.`);
    }
    const groupTeamIds = new Set(groupTeams.map((t) => t.id));
    const gm = groupMatches.filter((m) => groupTeamIds.has(m.homeTeamId) && groupTeamIds.has(m.awayTeamId));
    // World Cup groups use FIFA head-to-head tie-breakers, matching
    // Flutter's StandingsCalculator.calculate(..., fifaGroupTieBreakers: true).
    const computed = StandingsEngine.compute(groupTeams, gm, true);
    groupStandings[gid] = toRows(computed);
  }

  const result =
    worldCupFormat === 48
      ? seedWorldCupKnockouts48({ leagueId, groupStandings })
      : seedWorldCupKnockouts32({ leagueId, groupStandings });

  if (result.length === 0) throw new Error('Failed to seed the World Cup knockout bracket.');
  return result;
}
