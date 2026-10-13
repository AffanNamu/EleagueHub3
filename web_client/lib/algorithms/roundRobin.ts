//lib/algorithms
import { FixtureMatch } from '@/lib/models/leagueDetails';

export class RoundRobinGenerator {
  /**
   * Deterministic match id from (league, group, round, home, away) --
   * PHASE C: mirrors RoundRobinGenerator._matchId on the Dart side. A
   * random UUID meant a retried or re-run generation produced a second,
   * independent set of match documents instead of converging on the
   * same ones.
   */
  private static matchId({
    leagueId,
    groupId,
    roundNumber,
    homeTeamId,
    awayTeamId,
  }: {
    leagueId: string;
    groupId?: string | null;
    roundNumber: number;
    homeTeamId: string;
    awayTeamId: string;
  }): string {
    const g = (groupId || '').trim();
    return `${leagueId}-RR-${g || 'POOL'}-${roundNumber}-${homeTeamId}-${awayTeamId}`;
  }

  static generate({
    leagueId,
    teamIds,
    doubleRoundRobin,
    groupId = null,
    startRoundNumber = 1,
  }: {
    leagueId: string;
    teamIds: string[];
    doubleRoundRobin: boolean;
    groupId?: string | null;
    startRoundNumber?: number;
  }): Partial<FixtureMatch>[] {
    const now = Date.now();
    const ids = [...teamIds].sort();

    let bye: string | null = null;
    if (ids.length % 2 !== 0) {
      bye = '__BYE__';
      ids.push(bye);
    }

    const n = ids.length;
    if (n < 2) return [];

    let rotation = [...ids];
    const rounds = n - 1;
    const fixtures: Partial<FixtureMatch>[] = [];

    for (let r = 0; r < rounds; r++) {
      const pairs: [string, string][] = [];
      for (let i = 0; i < Math.floor(n / 2); i++) {
        const a = rotation[i];
        const b = rotation[n - 1 - i];
        if (a === bye || b === bye) continue;
        pairs.push([a, b]);
      }

      const swapRound = r % 2 !== 0;
      for (let i = 0; i < pairs.length; i++) {
        const [a, b] = pairs[i];
        const swapPair = i % 2 !== 0;
        // XOR equivalent in JS for booleans
        const swap = swapRound !== swapPair; 
        const home = swap ? b : a;
        const away = swap ? a : b;

        fixtures.push({
          id: this.matchId({ leagueId, groupId, roundNumber: startRoundNumber + r, homeTeamId: home, awayTeamId: away }),
          leagueId,
          groupId: groupId || null,
          roundNumber: startRoundNumber + r,
          homeTeamId: home,
          awayTeamId: away,
          homeScore: 0, // Match schema requires number or undefined
          awayScore: 0,
          status: 'scheduled',
          sortIndex: i,
          updatedAtMs: now,
          version: 1,
        });
      }
      rotation = this.rotate(rotation);
    }

    if (!doubleRoundRobin) return fixtures;

    // Generate Second Leg
    const secondLeg = fixtures.map((m) => ({
      ...m,
      id: this.matchId({
        leagueId,
        groupId,
        roundNumber: m.roundNumber! + rounds,
        homeTeamId: m.awayTeamId!,
        awayTeamId: m.homeTeamId!,
      }),
      roundNumber: m.roundNumber! + rounds,
      homeTeamId: m.awayTeamId,
      awayTeamId: m.homeTeamId,
      updatedAtMs: now,
    }));

    return [...fixtures, ...secondLeg];
  }

  private static rotate(list: string[]): string[] {
    if (list.length < 2) return list;
    const fixed = list[0];
    const rest = list.slice(1);
    const last = rest.pop()!;
    return [fixed, last, ...rest];
  }
}
