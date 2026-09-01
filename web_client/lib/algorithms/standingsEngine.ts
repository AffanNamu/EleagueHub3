import { Team } from '@/types/league';
import { FixtureMatch } from '@/types/match';

// FIXED: this engine used to sort using team.finalPoints / team.goalDifference /
// team.goalsFor read straight off the Team document, and StandingsTable.tsx
// separately read team.played / team.won / team.drawn / team.lost /
// team.goalsAgainst the same way. Those last five fields are never written
// anywhere in the Flutter codebase — leagues_repository_local.dart's
// updateMatchScoreAndUpdateTeamAggregates() only ever persists basePoints,
// adminAdjustment, finalPoints, goalDifference, and goalsFor to the team doc.
// So on web, P/W/D/L/GA silently showed 0 for every team in every league,
// while GF/GD/Pts happened to be correct.
//
// Flutter's own standings screen never has this problem because
// StandingsCalculator.calculate() (leagues/domain/standings/standings_calculator.dart)
// computes P/W/D/L/GF/GA fresh from the live match list every time — it never
// trusts persisted per-team counters for those fields. This engine now does
// the same: matchesPlayed/won/drawn/lost/goalsFor/goalsAgainst/basePoints are
// all derived from `matches`, and only `adminAdjustment` (which genuinely IS
// persisted by Flutter) is read off the team doc. finalPoints = computed
// basePoints + team.adminAdjustment, matching Flutter's definition exactly.

interface ComputedMatchStats {
  matchesPlayed: number;
  won: number;
  drawn: number;
  lost: number;
  goalsFor: number;
  goalsAgainst: number;
  goalDifference: number;
  basePoints: number;
}

function matchIsPlayed(m: FixtureMatch): boolean {
  return m.status === 'played' || m.status === 'completed' || m.isPlayed === true;
}

function computeMatchStats(teamId: string, matches: FixtureMatch[]): ComputedMatchStats {
  let matchesPlayed = 0;
  let won = 0;
  let drawn = 0;
  let lost = 0;
  let goalsFor = 0;
  let goalsAgainst = 0;

  for (const m of matches) {
    if (!matchIsPlayed(m)) continue;
    if (m.homeScore == null || m.awayScore == null) continue;

    if (m.homeTeamId === teamId) {
      matchesPlayed++;
      goalsFor += m.homeScore;
      goalsAgainst += m.awayScore;
      if (m.homeScore > m.awayScore) won++;
      else if (m.homeScore === m.awayScore) drawn++;
      else lost++;
    } else if (m.awayTeamId === teamId) {
      matchesPlayed++;
      goalsFor += m.awayScore;
      goalsAgainst += m.homeScore;
      if (m.awayScore > m.homeScore) won++;
      else if (m.awayScore === m.homeScore) drawn++;
      else lost++;
    }
  }

  return {
    matchesPlayed,
    won,
    drawn,
    lost,
    goalsFor,
    goalsAgainst,
    goalDifference: goalsFor - goalsAgainst,
    basePoints: won * 3 + drawn,
  };
}

export class StandingsEngine {
  /**
   * Computes standings by deriving P/W/D/L/GF/GA/basePoints from the raw
   * match list (matching Flutter's StandingsCalculator), then adding each
   * team's persisted adminAdjustment to get finalPoints.
   *
   * Sorting priority (unchanged):
   * 1) finalPoints DESC
   * 2) goalDifference DESC
   * 3) goalsFor DESC
   * 4) teamId ASC (stable deterministic fallback)
   *
   * If fifaGroupTieBreakers is true, ties on the first 3 metrics are resolved
   * by applying the exact same sorting rules ONLY to matches played among the
   * tied teams.
   */
  static compute(teams: Team[], matches: FixtureMatch[], fifaGroupTieBreakers: boolean = false): Team[] {
    const enriched: Team[] = teams.map((t) => {
      const stats = computeMatchStats(t.id, matches);
      const adminAdjustment = t.adminAdjustment || 0;
      return {
        ...t,
        played: stats.matchesPlayed,
        won: stats.won,
        drawn: stats.drawn,
        lost: stats.lost,
        goalsFor: stats.goalsFor,
        goalsAgainst: stats.goalsAgainst,
        goalDifference: stats.goalDifference,
        basePoints: stats.basePoints,
        adminAdjustment,
        finalPoints: stats.basePoints + adminAdjustment,
      };
    });

    const sorted = [...enriched];
    sorted.sort(this.baseCompare);

    if (!fifaGroupTieBreakers) {
      return sorted;
    }

    return this.applyFifaHeadToHeadTieBreakers(sorted, matches);
  }

  private static baseCompare(a: Team, b: Team): number {
    const fp = (b.finalPoints || 0) - (a.finalPoints || 0);
    if (fp !== 0) return fp;

    const gd = (b.goalDifference || 0) - (a.goalDifference || 0);
    if (gd !== 0) return gd;

    const gf = (b.goalsFor || 0) - (a.goalsFor || 0);
    if (gf !== 0) return gf;

    return a.id.localeCompare(b.id);
  }

  private static samePrimaryClusterKey(a: Team, b: Team): boolean {
    return (
      (a.finalPoints || 0) === (b.finalPoints || 0) &&
      (a.goalDifference || 0) === (b.goalDifference || 0) &&
      (a.goalsFor || 0) === (b.goalsFor || 0)
    );
  }

  private static applyFifaHeadToHeadTieBreakers(sorted: Team[], matches: FixtureMatch[]): Team[] {
    const out: Team[] = [];
    let i = 0;

    while (i < sorted.length) {
      let j = i + 1;
      while (j < sorted.length && this.samePrimaryClusterKey(sorted[i], sorted[j])) {
        j++;
      }

      // Single team, no tie
      if (j - i <= 1) {
        out.push(sorted[i]);
        i = j;
        continue;
      }

      // Resolve cluster
      const cluster = sorted.slice(i, j);
      out.push(...this.resolveClusterByHeadToHead(cluster, matches));
      i = j;
    }

    return out;
  }

  private static resolveClusterByHeadToHead(cluster: Team[], matches: FixtureMatch[]): Team[] {
    const ids = new Set(cluster.map(t => t.id));
    const h2h: Record<string, { points: number; gf: number; ga: number; gd: number }> = {};
    
    for (const id of ids) {
      h2h[id] = { points: 0, gf: 0, ga: 0, gd: 0 };
    }

    for (const m of matches) {
      if (!matchIsPlayed(m)) continue;
      if (!ids.has(m.homeTeamId) || !ids.has(m.awayTeamId)) continue;
      if (m.homeScore === undefined || m.homeScore === null || m.awayScore === undefined || m.awayScore === null) continue;

      const hs = m.homeScore;
      const as = m.awayScore;

      // goals
      h2h[m.homeTeamId].gf += hs;
      h2h[m.homeTeamId].ga += as;
      h2h[m.homeTeamId].gd = h2h[m.homeTeamId].gf - h2h[m.homeTeamId].ga;

      h2h[m.awayTeamId].gf += as;
      h2h[m.awayTeamId].ga += hs;
      h2h[m.awayTeamId].gd = h2h[m.awayTeamId].gf - h2h[m.awayTeamId].ga;

      // points
      if (hs > as) {
        h2h[m.homeTeamId].points += 3;
      } else if (hs < as) {
        h2h[m.awayTeamId].points += 3;
      } else {
        h2h[m.homeTeamId].points += 1;
        h2h[m.awayTeamId].points += 1;
      }
    }

    const sortedCluster = [...cluster];
    sortedCluster.sort((a, b) => {
      const sa = h2h[a.id];
      const sb = h2h[b.id];

      const p = sb.points - sa.points;
      if (p !== 0) return p;

      const gd = sb.gd - sa.gd;
      if (gd !== 0) return gd;

      const gf = sb.gf - sa.gf;
      if (gf !== 0) return gf;

      return a.id.localeCompare(b.id);
    });

    return sortedCluster;
  }
}
