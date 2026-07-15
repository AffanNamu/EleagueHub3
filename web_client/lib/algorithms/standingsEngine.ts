import { Team } from '@/types/league';
import { FixtureMatch } from '@/types/match';

export class StandingsEngine {
  static compute(teams: Team[], matches: FixtureMatch[]): Team[] {
    const sorted = [...teams];

    sorted.sort((a, b) => {
      // 1. Points (Descending)
      if (a.finalPoints !== b.finalPoints) {
        return (b.finalPoints || 0) - (a.finalPoints || 0);
      }

      // 2. Head-to-Head Points (Descending)
      const h2h = this.headToHeadCompare(a, b, matches);
      if (h2h !== 0) return h2h;

      // 3. Goal Difference (Descending)
      if (a.goalDifference !== b.goalDifference) {
        return (b.goalDifference || 0) - (a.goalDifference || 0);
      }

      // 4. Goals For (Descending)
      if (a.goalsFor !== b.goalsFor) {
        return (b.goalsFor || 0) - (a.goalsFor || 0);
      }

      // 5. Stable deterministic fallback
      return a.id.localeCompare(b.id);
    });

    return sorted;
  }

  private static headToHeadCompare(a: Team, b: Team, matches: FixtureMatch[]): number {
    let aPoints = 0;
    let bPoints = 0;

    for (const m of matches) {
      // Match status must be finished
      if (m.status !== 'played' && m.status !== 'completed') continue;
      if (m.homeScore === undefined || m.awayScore === undefined) continue;

      const isRelevant = 
        (m.homeTeamId === a.id && m.awayTeamId === b.id) ||
        (m.homeTeamId === b.id && m.awayTeamId === a.id);

      if (!isRelevant) continue;

      const homeGoals = m.homeScore;
      const awayGoals = m.awayScore;

      if (homeGoals === awayGoals) {
        aPoints += 1;
        bPoints += 1;
      } else if (homeGoals > awayGoals) {
        if (m.homeTeamId === a.id) aPoints += 3;
        else bPoints += 3;
      } else {
        if (m.awayTeamId === a.id) aPoints += 3;
        else bPoints += 3;
      }
    }

    // We want descending order, so return b - a
    return bPoints - aPoints;
  }
}
