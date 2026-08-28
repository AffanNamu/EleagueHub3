import { Team } from '@/types/league';
import { FixtureMatch } from '@/types/match';

export class StandingsEngine {
  /**
   * Computes standings exactly matching Flutter's StandingsCalculator.
   * Sorting priority:
   * 1) finalPoints DESC (base points + adminAdjustment)
   * 2) goalDifference DESC
   * 3) goalsFor DESC
   * 4) teamId ASC (stable deterministic fallback)
   *
   * If fifaGroupTieBreakers is true, ties on the first 3 metrics are resolved
   * by applying the exact same sorting rules ONLY to matches played among the tied teams.
   */
  static compute(teams: Team[], matches: FixtureMatch[], fifaGroupTieBreakers: boolean = false): Team[] {
    const sorted = [...teams];

    // Standard sorting
    sorted.sort(this.baseCompare);

    if (!fifaGroupTieBreakers) {
      return sorted;
    }

    // Apply FIFA Head-to-Head for ties
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
      if (m.status !== 'played' && m.status !== 'completed' && !m.isPlayed) continue;
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
