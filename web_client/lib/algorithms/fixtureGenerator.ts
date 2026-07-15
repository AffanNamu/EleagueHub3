import { RoundRobinGenerator } from './roundRobin';
import { FixtureMatch } from '@/types/match';
import { Team, League } from '@/types/league';

export class FixtureGenerator {
  static generateClassicLeagueFixtures(league: League, teams: Team[]): Partial<FixtureMatch>[] {
    if (teams.length < 2) throw new Error("At least 2 teams required.");
    return RoundRobinGenerator.generate({
      leagueId: league.id,
      teamIds: teams.map(t => t.id),
      doubleRoundRobin: league.settings.doubleRoundRobin ?? true,
      startRoundNumber: 1,
    });
  }

  static generateGroupStage(league: League, teams: Team[]): Partial<FixtureMatch>[] {
    const byGroup: Record<string, Team[]> = {};
    for (const t of teams) {
      const gid = t.groupId?.trim();
      if (!gid) throw new Error(`Team ${t.name} has no group assigned.`);
      if (!byGroup[gid]) byGroup[gid] = [];
      byGroup[gid].push(t);
    }

    let allFixtures: Partial<FixtureMatch>[] = [];
    const groupKeys = Object.keys(byGroup).sort();

    for (const gid of groupKeys) {
      const ids = byGroup[gid].map(t => t.id);
      
      // World Cup format is strictly single round robin
      const isWorldCup = league.format === 'worldCup';
      
      const groupFixtures = RoundRobinGenerator.generate({
        leagueId: league.id,
        teamIds: ids,
        doubleRoundRobin: isWorldCup ? false : (league.settings.doubleRoundRobin ?? true),
        groupId: gid,
        startRoundNumber: 1,
      });
      
      allFixtures = [...allFixtures, ...groupFixtures];
    }

    return allFixtures;
  }
}
