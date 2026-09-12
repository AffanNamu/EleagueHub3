// lib/algorithms/swissPairing.ts
//
// Mirrors lib/features/leagues/domain/algorithms/swiss_pairing.dart —
// the Swiss-pairing engine for the uclSwiss league format:
//   - Allowed team counts: 18 or 36 (no byes)
//   - Round 1: deterministic shuffle (seeded by leagueId + round number)
//   - Later rounds: pair teams by ranking proximity, STRICTLY avoiding
//     rematches, using a backtracking perfect-matching builder (not
//     greedy) so it never gets stuck when a valid pairing exists.
//
// This is a completely separate code path from RoundRobinGenerator —
// Swiss-format leagues generate ONE round at a time (organizer clicks
// "Generate Next Round" after every match in the current round finishes),
// not a full schedule upfront.

import { v4 as uuidv4 } from 'uuid';
import { FixtureMatch, Team } from '@/lib/models/leagueDetails';

function fnv1a32(input: string): number {
  const fnvOffsetBasis = 0x811c9dc5;
  const fnvPrime = 0x01000193;
  let hash = fnvOffsetBasis;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, fnvPrime) >>> 0;
  }
  return hash & 0x7fffffff;
}

function stableSeed(leagueId: string, roundNumber: number): number {
  return (fnv1a32(leagueId) ^ roundNumber) & 0x7fffffff;
}

/** Small seeded PRNG (mulberry32) — deterministic per (leagueId, round), unlike Math.random(). */
function makeRandom(seed: number) {
  let a = seed >>> 0;
  return {
    next(): number {
      a |= 0;
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    },
    nextInt(maxExclusive: number): number {
      return Math.floor(this.next() * maxExclusive);
    },
  };
}

function shuffle<T>(list: T[], rand: ReturnType<typeof makeRandom>): T[] {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = rand.nextInt(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

function allowedTeamCount(n: number): boolean {
  return n === 18 || n === 36;
}

function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

function matchIsPlayed(m: FixtureMatch): boolean {
  return (m.status === 'played' || m.status === 'completed' || m.isPlayed === true) && m.homeScore != null && m.awayScore != null;
}

function homeCounts(teams: Team[], matches: FixtureMatch[], beforeRound: number): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const t of teams) counts[t.id] = 0;
  for (const m of matches) {
    if (m.roundNumber >= beforeRound) continue;
    counts[m.homeTeamId] = (counts[m.homeTeamId] || 0) + 1;
  }
  return counts;
}

function awayCounts(teams: Team[], matches: FixtureMatch[], beforeRound: number): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const t of teams) counts[t.id] = 0;
  for (const m of matches) {
    if (m.roundNumber >= beforeRound) continue;
    counts[m.awayTeamId] = (counts[m.awayTeamId] || 0) + 1;
  }
  return counts;
}

interface Pair {
  home: string;
  away: string;
}

/** Build a full non-rematch pairing using backtracking perfect matching. Returns [] if none exists. */
function buildPairingBacktracking({
  teamIds,
  rankIndex,
  previousPairs,
  homeCount,
  awayCount,
  rand,
  totalRounds,
}: {
  teamIds: string[];
  rankIndex: Record<string, number>;
  previousPairs: Set<string>;
  homeCount: Record<string, number>;
  awayCount: Record<string, number>;
  rand: ReturnType<typeof makeRandom>;
  totalRounds: number;
}): Pair[] {
  const maxHome = Math.floor(totalRounds / 2);
  const maxAway = totalRounds - maxHome;

  const randWeight: Record<string, number> = {};
  for (const id of teamIds) randWeight[id] = rand.nextInt(1 << 30);

  const unpaired = new Set(teamIds);
  const result: Pair[] = [];

  function candidateCount(a: string): number {
    let c = 0;
    for (const b of unpaired) {
      if (b === a) continue;
      if (previousPairs.has(pairKey(a, b))) continue;
      c++;
    }
    return c;
  }

  function candidatesFor(a: string): string[] {
    const aRank = rankIndex[a] ?? 999999;
    const list: string[] = [];
    for (const b of unpaired) {
      if (b === a) continue;
      if (previousPairs.has(pairKey(a, b))) continue;
      list.push(b);
    }
    list.sort((b1, b2) => {
      const d1 = Math.abs((rankIndex[b1] ?? 999999) - aRank);
      const d2 = Math.abs((rankIndex[b2] ?? 999999) - aRank);
      if (d1 !== d2) return d1 - d2;
      const c1 = candidateCount(b1);
      const c2 = candidateCount(b2);
      if (c1 !== c2) return c1 - c2;
      return (randWeight[b1] || 0) - (randWeight[b2] || 0);
    });
    return list;
  }

  const canHome = (id: string) => (homeCount[id] || 0) < maxHome;
  const canAway = (id: string) => (awayCount[id] || 0) < maxAway;
  const mustAway = (id: string) => !canHome(id);
  const mustHome = (id: string) => !canAway(id);

  function orientations(a: string, b: string): Pair[] {
    const out: Pair[] = [];
    if (!mustAway(a) && !mustHome(b) && canHome(a) && canAway(b)) out.push({ home: a, away: b });
    if (!mustAway(b) && !mustHome(a) && canHome(b) && canAway(a)) out.push({ home: b, away: a });
    out.sort((x, y) => {
      const hx = homeCount[x.home] || 0;
      const hy = homeCount[y.home] || 0;
      if (hx !== hy) return hx - hy;
      return (randWeight[x.home] || 0) - (randWeight[y.home] || 0);
    });
    return out;
  }

  function backtrack(): boolean {
    if (unpaired.size === 0) return true;

    let a: string | null = null;
    let best = 1 << 30;
    for (const id of unpaired) {
      const c = candidateCount(id);
      if (c < best) {
        best = c;
        a = id;
        if (best === 0) break;
      }
    }
    if (a === null || best === 0) return false;

    const cand = candidatesFor(a);
    for (const b of cand) {
      if (!unpaired.has(b)) continue;
      const key = pairKey(a, b);
      if (previousPairs.has(key)) continue;

      const opts = orientations(a, b);
      if (opts.length === 0) continue;

      unpaired.delete(a);
      unpaired.delete(b);
      previousPairs.add(key);

      for (const opt of opts) {
        homeCount[opt.home] = (homeCount[opt.home] || 0) + 1;
        awayCount[opt.away] = (awayCount[opt.away] || 0) + 1;
        result.push(opt);

        if (backtrack()) return true;

        result.pop();
        homeCount[opt.home] = (homeCount[opt.home] || 1) - 1;
        awayCount[opt.away] = (awayCount[opt.away] || 1) - 1;
      }

      previousPairs.delete(key);
      unpaired.add(a);
      unpaired.add(b);
    }

    return false;
  }

  const ok = backtrack();
  return ok ? result : [];
}

function buildFixtures(leagueId: string, roundNumber: number, pairs: Pair[]): Partial<FixtureMatch>[] {
  const now = Date.now();
  return pairs.map((p, i) => ({
    id: uuidv4(),
    leagueId,
    groupId: null,
    roundNumber,
    homeTeamId: p.home,
    awayTeamId: p.away,
    homeScore: null,
    awayScore: null,
    status: 'scheduled' as const,
    sortIndex: i,
    updatedAtMs: now,
    version: 1,
  }));
}

export const SwissPairingEngine = {
  /** Generate Round 1 pairings (deterministic per league). */
  generateInitialRound({
    leagueId,
    teams,
    roundNumber,
    totalRounds = 8,
  }: {
    leagueId: string;
    teams: Team[];
    roundNumber: number;
    totalRounds?: number;
  }): Partial<FixtureMatch>[] {
    if (teams.length < 2) return [];
    if (!allowedTeamCount(teams.length)) return [];
    if (teams.length % 2 !== 0) return [];

    const rand = makeRandom(stableSeed(leagueId, roundNumber));
    const shuffled = shuffle(teams, rand);
    const ids = shuffled.map((t) => t.id);

    const previousPairs = new Set<string>();
    const rankIndex: Record<string, number> = {};
    ids.forEach((id, i) => (rankIndex[id] = i));

    const homeCount: Record<string, number> = {};
    const awayCount: Record<string, number> = {};
    for (const t of teams) {
      homeCount[t.id] = 0;
      awayCount[t.id] = 0;
    }

    const pairs = buildPairingBacktracking({
      teamIds: ids,
      rankIndex,
      previousPairs,
      homeCount,
      awayCount,
      rand,
      totalRounds,
    });
    if (pairs.length === 0) return [];

    return buildFixtures(leagueId, roundNumber, pairs);
  },

  /**
   * Generate the next Swiss round pairings.
   * - STRICT no-rematch enforcement across all rounds already generated.
   * - Uses played matches only to compute standings ordering, but uses
   *   ALL generated matches (played or not) to block rematches.
   */
  generateNextRound({
    leagueId,
    teams,
    existingMatches,
    nextRoundNumber,
    totalRounds = 8,
  }: {
    leagueId: string;
    teams: Team[];
    existingMatches: FixtureMatch[];
    nextRoundNumber: number;
    totalRounds?: number;
  }): Partial<FixtureMatch>[] {
    if (teams.length < 2) return [];
    if (!allowedTeamCount(teams.length)) return [];
    if (teams.length % 2 !== 0) return [];

    const rand = makeRandom(stableSeed(leagueId, nextRoundNumber));

    const previousPairs = new Set<string>();
    for (const m of existingMatches) {
      if (m.roundNumber < nextRoundNumber) previousPairs.add(pairKey(m.homeTeamId, m.awayTeamId));
    }

    const played = existingMatches.filter((m) => m.roundNumber < nextRoundNumber && matchIsPlayed(m));

    const points: Record<string, number> = {};
    const goalsFor: Record<string, number> = {};
    const goalsAgainst: Record<string, number> = {};
    for (const t of teams) {
      points[t.id] = 0;
      goalsFor[t.id] = 0;
      goalsAgainst[t.id] = 0;
    }

    for (const m of played) {
      const hs = m.homeScore as number;
      const as = m.awayScore as number;
      goalsFor[m.homeTeamId] = (goalsFor[m.homeTeamId] || 0) + hs;
      goalsAgainst[m.homeTeamId] = (goalsAgainst[m.homeTeamId] || 0) + as;
      goalsFor[m.awayTeamId] = (goalsFor[m.awayTeamId] || 0) + as;
      goalsAgainst[m.awayTeamId] = (goalsAgainst[m.awayTeamId] || 0) + hs;
      if (hs > as) points[m.homeTeamId] = (points[m.homeTeamId] || 0) + 3;
      else if (hs === as) {
        points[m.homeTeamId] = (points[m.homeTeamId] || 0) + 1;
        points[m.awayTeamId] = (points[m.awayTeamId] || 0) + 1;
      } else points[m.awayTeamId] = (points[m.awayTeamId] || 0) + 3;
    }

    const orderedIds = teams
      .map((t) => t.id)
      .sort((a, b) => {
        const p = (points[b] || 0) - (points[a] || 0);
        if (p !== 0) return p;
        const gdA = (goalsFor[a] || 0) - (goalsAgainst[a] || 0);
        const gdB = (goalsFor[b] || 0) - (goalsAgainst[b] || 0);
        if (gdB !== gdA) return gdB - gdA;
        const gfDiff = (goalsFor[b] || 0) - (goalsFor[a] || 0);
        if (gfDiff !== 0) return gfDiff;
        return a.localeCompare(b);
      });

    const rankIndex: Record<string, number> = {};
    orderedIds.forEach((id, i) => (rankIndex[id] = i));

    const homeCount = homeCounts(teams, existingMatches, nextRoundNumber);
    const awayCount = awayCounts(teams, existingMatches, nextRoundNumber);

    const pairs = buildPairingBacktracking({
      teamIds: orderedIds,
      rankIndex,
      previousPairs,
      homeCount,
      awayCount,
      rand,
      totalRounds,
    });
    if (pairs.length === 0) return [];

    return buildFixtures(leagueId, nextRoundNumber, pairs);
  },
};
