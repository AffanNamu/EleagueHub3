// lib/algorithms/worldCupGrouping.ts
//
// Mirrors add_teams_screen.dart's _autoAssignWorldCupGroups — the
// deterministic shuffle used to auto-place World Cup teams into groups
// of 4 when the organizer hasn't manually assigned them (or the existing
// assignment doesn't form a valid structure). Sorts teams by id first for
// a stable base order, then shuffles with a seed derived from the
// leagueId so the same league always gets the same group draw across
// sessions/devices — not a fresh random draw every time fixtures are
// generated.

import { fnv1a32, makeRandom, shuffle } from './deterministicRandom';

export function autoAssignWorldCupGroups<T extends { id: string }>(
  teams: T[],
  leagueId: string,
  groups: string[],
): (T & { groupId: string })[] {
  const sorted = [...teams].sort((a, b) => a.id.localeCompare(b.id));
  const rand = makeRandom(fnv1a32(leagueId));
  const shuffled = shuffle(sorted, rand);

  return shuffled.map((t, i) => ({
    ...t,
    groupId: groups[Math.floor(i / 4)],
  }));
}
