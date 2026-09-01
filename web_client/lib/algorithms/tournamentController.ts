// lib/algorithms/tournamentController.ts
//
// Direct TS port of lib/features/leagues/domain/logic/tournament_controller.dart.
// This is the piece that actually builds and seeds knockout brackets — the
// web LeagueDetailScreenClient previously had three buttons ("Generate
// Swiss/Group/World Cup Knockouts") that just called alert('... triggered.')
// with no logic behind them at all. This file ports the real algorithm;
// lib/leagues/knockoutGeneration.ts wires it to live standings data.
//
// NOTE ON ASSUMED FIELDS: knockout_match.dart itself was not shared, only
// tournament_controller.dart, discussion_thread-adjacent Firestore rules,
// and every call site that reads/writes it. `isMatchFinished` and
// `winnerTeamId` below are inferred from those call sites (Firestore rules'
// validWorldCupKnockoutFields() lists winnerId/loserId as valid optional
// fields; processMatchResult reads completedMatch.winnerTeamId as a getter
// derived from scores, falling back to tiebreakWinnerTeamId on a draw). If
// the real Dart getters differ, only these two functions need correcting —
// nothing else in this file depends on their internals.

export type KnockoutMatchStatus = 'scheduled' | 'completed' | 'played';

export interface KnockoutMatch {
  id: string;
  leagueId: string;
  roundName: string;
  homeTeamId: string | null;
  awayTeamId: string | null;
  homeScore: number | null;
  awayScore: number | null;
  status: KnockoutMatchStatus;
  tiebreakWinnerTeamId: string | null;
  nextMatchId: string | null;
  loserGoesToMatchId: string | null;
  isSecondLeg: boolean;
}

/// Minimal shape needed for seeding — matches Dart's StandingsRow fields
/// that this controller actually reads (teamId, gd, gf, finalPoints).
/// Callers (knockoutGeneration.ts) adapt full Team/StandingsRow objects
/// down to this before calling into here.
export interface StandingsRowLike {
  teamId: string;
  finalPoints: number;
  gd: number;
  gf: number;
}

/// Represents a team that has qualified from the World Cup group stage,
/// along with how they qualified. Ported for parity with the Dart file;
/// not currently consumed elsewhere in this port.
export interface WorldCupQualifiedTeam {
  teamId: string;
  groupId: string;
  slot: 'winner' | 'runnerUp' | 'bestThird';
  slotRank: number;
}

type KoSlot = 'home' | 'away';

function shortCode(roundName: string): string {
  switch (roundName) {
    case 'Play-off':
      return 'PO';
    case 'Round of 32':
      return 'R32';
    case 'Round of 16':
      return 'R16';
    case 'Quarter Finals':
      return 'QF';
    case 'Semi Finals':
      return 'SF';
    case 'Final':
      return 'F';
    case '3rd Place':
      return '3P';
    default:
      return 'KO';
  }
}

function nextRoundName(current: string): string {
  switch (current) {
    case 'Round of 32':
      return 'Round of 16';
    case 'Round of 16':
      return 'Quarter Finals';
    case 'Quarter Finals':
      return 'Semi Finals';
    case 'Semi Finals':
      return 'Final';
    default:
      return '';
  }
}

/// Builds a KO tree skeleton from a specified start round. Wires
/// nextMatchId from each match to the next round match. Supports
/// 'Round of 32' as a start round for FIFA 2026.
function buildKnockoutTree({
  leagueId,
  startRoundName,
  startRoundMatchCount,
  idPrefix,
  nowMs,
  includeThirdPlace = false,
}: {
  leagueId: string;
  startRoundName: string;
  startRoundMatchCount: number;
  idPrefix: string;
  nowMs: number;
  includeThirdPlace?: boolean;
}): KnockoutMatch[] {
  const id = (prefix: string, index: number) => `${leagueId}-${idPrefix}-${prefix}-${nowMs}_${index}`;

  const rounds: Record<string, KnockoutMatch[]> = {};

  let matchCount = startRoundMatchCount;
  let roundName = startRoundName;

  // eslint-disable-next-line no-constant-condition
  while (true) {
    const list: KnockoutMatch[] = [];
    for (let i = 0; i < matchCount; i++) {
      list.push({
        id: id(shortCode(roundName), i + 1),
        leagueId,
        roundName,
        homeTeamId: null,
        awayTeamId: null,
        homeScore: null,
        awayScore: null,
        status: 'scheduled',
        tiebreakWinnerTeamId: null,
        nextMatchId: null,
        loserGoesToMatchId: null,
        isSecondLeg: false,
      });
    }
    rounds[roundName] = list;

    if (matchCount === 1) break; // Final created

    matchCount = Math.floor(matchCount / 2);
    roundName = nextRoundName(roundName);
    if (!roundName) break;
  }

  // Ordered round names from start to Final.
  const orderedRoundNames: string[] = [];
  if (startRoundName === 'Round of 32') {
    orderedRoundNames.push('Round of 32', 'Round of 16', 'Quarter Finals', 'Semi Finals', 'Final');
  } else if (startRoundName === 'Round of 16') {
    orderedRoundNames.push('Round of 16', 'Quarter Finals', 'Semi Finals', 'Final');
  } else if (startRoundName === 'Quarter Finals') {
    orderedRoundNames.push('Quarter Finals', 'Semi Finals', 'Final');
  } else if (startRoundName === 'Semi Finals') {
    orderedRoundNames.push('Semi Finals', 'Final');
  } else if (startRoundName === 'Final') {
    orderedRoundNames.push('Final');
  }

  // Wire nextMatchId between rounds.
  for (let i = 0; i + 1 < orderedRoundNames.length; i++) {
    const from = [...(rounds[orderedRoundNames[i]] ?? [])];
    const to = rounds[orderedRoundNames[i + 1]] ?? [];

    if (to.length === 0) continue;

    for (let j = 0; j < from.length; j++) {
      const nextIndex = Math.floor(j / 2);
      if (nextIndex >= to.length) continue;
      from[j] = { ...from[j], nextMatchId: to[nextIndex].id };
    }

    rounds[orderedRoundNames[i]] = from;
  }

  // Optional 3rd place if explicitly enabled.
  let thirdPlace: KnockoutMatch | null = null;
  if (includeThirdPlace && rounds['Semi Finals']) {
    thirdPlace = {
      id: id('3P', 1),
      leagueId,
      roundName: '3rd Place',
      homeTeamId: null,
      awayTeamId: null,
      homeScore: null,
      awayScore: null,
      status: 'scheduled',
      tiebreakWinnerTeamId: null,
      nextMatchId: null,
      loserGoesToMatchId: null,
      isSecondLeg: false,
    };

    const semis = [...(rounds['Semi Finals'] ?? [])];
    if (semis.length > 0) semis[0] = { ...semis[0], loserGoesToMatchId: thirdPlace.id };
    if (semis.length > 1) semis[1] = { ...semis[1], loserGoesToMatchId: thirdPlace.id };
    rounds['Semi Finals'] = semis;
  }

  // Flatten output in display order.
  const out: KnockoutMatch[] = [];
  for (const rn of orderedRoundNames) {
    out.push(...(rounds[rn] ?? []));
  }
  if (thirdPlace) out.push(thirdPlace);

  return out;
}

function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

function seedIndexFromId(id: string): number {
  const idx = id.lastIndexOf('_');
  if (idx === -1 || idx + 1 >= id.length) return 0;
  const raw = id.substring(idx + 1);
  const parsed = parseInt(raw, 10);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function slotForAdvancement(fromMatch: KnockoutMatch, allMatches: KnockoutMatch[]): KoSlot {
  const nextId = fromMatch.nextMatchId;
  if (nextId == null) return 'home';

  const feeders = allMatches.filter((m) => m.roundName === fromMatch.roundName && m.nextMatchId === nextId);

  if (feeders.length <= 1) return 'home';

  feeders.sort((a, b) => {
    const ai = seedIndexFromId(a.id);
    const bi = seedIndexFromId(b.id);
    if (ai !== bi) return ai - bi;
    return a.id.localeCompare(b.id);
  });

  const pos = feeders.findIndex((m) => m.id === fromMatch.id);
  const safePos = Math.max(0, pos);
  return safePos % 2 === 0 ? 'home' : 'away';
}

function advanceWinnerToNext(completedMatch: KnockoutMatch, winnerId: string, allMatches: KnockoutMatch[]): KnockoutMatch[] {
  const nextId = completedMatch.nextMatchId;
  if (nextId == null) return allMatches;

  const slot = slotForAdvancement(completedMatch, allMatches);

  return allMatches.map((m) => {
    if (m.id !== nextId) return m;
    return slot === 'home' ? { ...m, homeTeamId: winnerId } : { ...m, awayTeamId: winnerId };
  });
}

function placeLoserToThirdPlace(completedSemiFinal: KnockoutMatch, loserId: string, allMatches: KnockoutMatch[]): KnockoutMatch[] {
  const thirdId = completedSemiFinal.loserGoesToMatchId;
  if (thirdId == null) return allMatches;

  const semiFeeders = allMatches.filter((m) => m.roundName === 'Semi Finals' && m.loserGoesToMatchId === thirdId);
  if (semiFeeders.length === 0) return allMatches;

  semiFeeders.sort((a, b) => {
    const ai = seedIndexFromId(a.id);
    const bi = seedIndexFromId(b.id);
    if (ai !== bi) return ai - bi;
    return a.id.localeCompare(b.id);
  });

  const pos = semiFeeders.findIndex((m) => m.id === completedSemiFinal.id);
  const safePos = Math.max(0, pos);
  const slot: KoSlot = safePos % 2 === 0 ? 'home' : 'away';

  return allMatches.map((m) => {
    if (m.id !== thirdId) return m;
    return slot === 'home' ? { ...m, homeTeamId: loserId } : { ...m, awayTeamId: loserId };
  });
}

// ── UCL GROUP MODEL seeding (16 or 32 teams) ────────────────────────────────

export function seedKnockoutsFromGroups({
  leagueId,
  groupStandings,
}: {
  leagueId: string;
  groupStandings: Record<string, StandingsRowLike[]>;
}): KnockoutMatch[] {
  const keys = Object.keys(groupStandings).sort();
  if (keys.length === 0) return [];

  const now = Date.now();
  const groupCount = keys.length;

  if (groupCount !== 4 && groupCount !== 8) return [];

  for (const k of keys) {
    const rows = groupStandings[k] ?? [];
    if (rows.length !== 4) return [];
  }

  const winners = keys.map((k) => groupStandings[k][0]);
  const runners = keys.map((k) => groupStandings[k][1]);

  const startRoundName = groupCount === 8 ? 'Round of 16' : 'Quarter Finals';
  const startMatchCount = groupCount === 8 ? 8 : 4;

  const tree = buildKnockoutTree({
    leagueId,
    startRoundName,
    startRoundMatchCount: startMatchCount,
    idPrefix: 'GRP',
    nowMs: now,
    includeThirdPlace: false,
  });

  const startRound = tree.filter((m) => m.roundName === startRoundName);
  if (startRound.length !== startMatchCount) return [];

  // Pair groups in twos: A1 vs B2, B1 vs A2, etc.
  const seeded: KnockoutMatch[] = [];
  let idx = 0;
  for (let i = 0; i + 1 < winners.length; i += 2) {
    const g1Winner = winners[i];
    const g2Winner = winners[i + 1];
    const g1Runner = runners[i];
    const g2Runner = runners[i + 1];

    seeded.push({ ...startRound[idx++], homeTeamId: g1Winner.teamId, awayTeamId: g2Runner.teamId });
    seeded.push({ ...startRound[idx++], homeTeamId: g2Winner.teamId, awayTeamId: g1Runner.teamId });
  }

  const seededById = new Map(seeded.map((m) => [m.id, m]));
  return tree.map((m) => seededById.get(m.id) ?? m);
}

// ── UCL SWISS MODEL seeding (18 or 36 teams) ────────────────────────────────

export function seedSwissKnockouts({
  leagueId,
  swissStandings,
}: {
  leagueId: string;
  swissStandings: StandingsRowLike[];
}): KnockoutMatch[] {
  const n = swissStandings.length;
  if (n !== 36 && n !== 18) return [];

  const now = Date.now();
  const id = (prefix: string, index: number) => `${leagueId}-SWISS-${prefix}-${now}_${index}`;

  const buildTier = (autoCount: number, playoffCount: number, startRoundName: string, startMatchCount: number) => {
    const autoQualifiers = swissStandings.slice(0, autoCount);
    const playoffSeeds = swissStandings.slice(autoCount, autoCount + playoffCount);
    if (playoffSeeds.length !== playoffCount) return [];

    const tree = buildKnockoutTree({
      leagueId,
      startRoundName,
      startRoundMatchCount: startMatchCount,
      idPrefix: 'SWISS',
      nowMs: now,
      includeThirdPlace: false,
    });

    const startRound = tree.filter((m) => m.roundName === startRoundName);
    if (startRound.length !== startMatchCount) return [];

    const seededStart: KnockoutMatch[] = [];
    for (let i = 0; i < startMatchCount; i++) {
      seededStart.push({ ...startRound[i], homeTeamId: autoQualifiers[i].teamId, awayTeamId: null });
    }

    const playoffMatches: KnockoutMatch[] = [];
    let start = 0;
    let end = playoffSeeds.length - 1;

    for (let tieIndex = 0; tieIndex < startMatchCount; tieIndex++) {
      const a = playoffSeeds[start++];
      const b = playoffSeeds[end--];
      const startRoundIndex = startMatchCount - 1 - tieIndex;

      playoffMatches.push({
        id: id('PO1', tieIndex + 1),
        leagueId,
        roundName: 'Play-off',
        homeTeamId: a.teamId,
        awayTeamId: b.teamId,
        homeScore: null,
        awayScore: null,
        status: 'scheduled',
        tiebreakWinnerTeamId: null,
        nextMatchId: seededStart[startRoundIndex].id,
        loserGoesToMatchId: null,
        isSecondLeg: false,
      });

      playoffMatches.push({
        id: id('PO2', tieIndex + 1),
        leagueId,
        roundName: 'Play-off',
        homeTeamId: b.teamId,
        awayTeamId: a.teamId,
        homeScore: null,
        awayScore: null,
        status: 'scheduled',
        tiebreakWinnerTeamId: null,
        nextMatchId: seededStart[startRoundIndex].id,
        loserGoesToMatchId: null,
        isSecondLeg: true,
      });
    }

    const seededById = new Map(seededStart.map((m) => [m.id, m]));
    const updatedTree = tree.map((m) => seededById.get(m.id) ?? m);

    return [...playoffMatches, ...updatedTree];
  };

  if (n === 36) return buildTier(8, 16, 'Round of 16', 8);
  return buildTier(4, 8, 'Quarter Finals', 4); // n === 18
}

// ── World Cup 32-team knockout seeding (FIFA 2022) ──────────────────────────

interface WcPairing {
  home: string;
  away: string;
}

export function seedWorldCupKnockouts32({
  leagueId,
  groupStandings,
}: {
  leagueId: string;
  groupStandings: Record<string, StandingsRowLike[]>;
}): KnockoutMatch[] {
  const keys = Object.keys(groupStandings).sort();
  if (keys.length !== 8) return [];

  for (const k of keys) {
    const rows = groupStandings[k] ?? [];
    if (rows.length !== 4) return [];
  }

  const now = Date.now();

  const tree = buildKnockoutTree({
    leagueId,
    startRoundName: 'Round of 16',
    startRoundMatchCount: 8,
    idPrefix: 'WC32',
    nowMs: now,
    includeThirdPlace: true,
  });

  const r16 = tree.filter((m) => m.roundName === 'Round of 16');
  if (r16.length !== 8) return [];

  const w: Record<string, string> = {};
  const r: Record<string, string> = {};
  for (const k of keys) {
    const rows = groupStandings[k];
    w[k] = rows[0].teamId;
    r[k] = rows[1].teamId;
  }

  // Official FIFA 2022 R16 pairings.
  const pairings: WcPairing[] = [
    { home: w[keys[0]], away: r[keys[1]] }, // 1A vs 2B
    { home: w[keys[2]], away: r[keys[3]] }, // 1C vs 2D
    { home: w[keys[1]], away: r[keys[0]] }, // 1B vs 2A
    { home: w[keys[3]], away: r[keys[2]] }, // 1D vs 2C
    { home: w[keys[4]], away: r[keys[5]] }, // 1E vs 2F
    { home: w[keys[6]], away: r[keys[7]] }, // 1G vs 2H
    { home: w[keys[5]], away: r[keys[4]] }, // 1F vs 2E
    { home: w[keys[7]], away: r[keys[6]] }, // 1H vs 2G
  ];

  const seeded: KnockoutMatch[] = r16.map((m, i) => ({ ...m, homeTeamId: pairings[i].home, awayTeamId: pairings[i].away }));

  const seededById = new Map(seeded.map((m) => [m.id, m]));
  return tree.map((m) => seededById.get(m.id) ?? m);
}

// ── World Cup 48-team knockout seeding (FIFA 2026) ──────────────────────────

export function seedWorldCupKnockouts48({
  leagueId,
  groupStandings,
}: {
  leagueId: string;
  groupStandings: Record<string, StandingsRowLike[]>;
}): KnockoutMatch[] {
  const keys = Object.keys(groupStandings).sort();
  if (keys.length !== 12) return [];

  for (const k of keys) {
    const rows = groupStandings[k] ?? [];
    if (rows.length !== 4) return [];
  }

  const now = Date.now();

  const tree = buildKnockoutTree({
    leagueId,
    startRoundName: 'Round of 32',
    startRoundMatchCount: 16,
    idPrefix: 'WC48',
    nowMs: now,
    includeThirdPlace: true,
  });

  const r32 = tree.filter((m) => m.roundName === 'Round of 32');
  if (r32.length !== 16) return [];

  const groupWinners: StandingsRowLike[] = [];
  const groupRunnersUp: StandingsRowLike[] = [];
  const allThirdPlaced: StandingsRowLike[] = [];

  for (const k of keys) {
    const rows = groupStandings[k];
    groupWinners.push(rows[0]);
    groupRunnersUp.push(rows[1]);
    if (rows.length >= 3) allThirdPlaced.push(rows[2]);
  }

  // 8 best third-placed: points DESC, GD DESC, GF DESC, teamId ASC (stable).
  allThirdPlaced.sort((a, b) => {
    const pts = b.finalPoints - a.finalPoints;
    if (pts !== 0) return pts;
    const gd = b.gd - a.gd;
    if (gd !== 0) return gd;
    const gf = b.gf - a.gf;
    if (gf !== 0) return gf;
    return a.teamId.localeCompare(b.teamId);
  });

  const bestThird = allThirdPlaced.slice(0, 8);
  if (bestThird.length < 8) return [];

  // Slots 0-7: Winners A-H vs Best 3rd ranked 1-8.
  const seeded: KnockoutMatch[] = [];
  for (let i = 0; i < 8; i++) {
    seeded.push({ ...r32[i], homeTeamId: groupWinners[i].teamId, awayTeamId: bestThird[i].teamId });
  }

  // Slots 8-11: Runners-up A-H paired in adjacent groups.
  for (let i = 0; i < 4; i++) {
    const homeRunner = groupRunnersUp[i * 2];
    const awayRunner = groupRunnersUp[i * 2 + 1];
    seeded.push({ ...r32[8 + i], homeTeamId: homeRunner.teamId, awayTeamId: awayRunner.teamId });
  }

  // Slots 12-15: Winners I-L vs Runners-up I-L (cross-paired).
  const winnersIL = groupWinners.slice(8, 12);
  const runnersIL = groupRunnersUp.slice(8, 12);

  seeded.push({ ...r32[12], homeTeamId: winnersIL[0].teamId, awayTeamId: runnersIL[1].teamId }); // 1I vs 2J
  seeded.push({ ...r32[13], homeTeamId: winnersIL[2].teamId, awayTeamId: runnersIL[3].teamId }); // 1K vs 2L
  seeded.push({ ...r32[14], homeTeamId: winnersIL[1].teamId, awayTeamId: runnersIL[0].teamId }); // 1J vs 2I
  seeded.push({ ...r32[15], homeTeamId: winnersIL[3].teamId, awayTeamId: runnersIL[2].teamId }); // 1L vs 2K

  const seededById = new Map(seeded.map((m) => [m.id, m]));
  return tree.map((m) => seededById.get(m.id) ?? m);
}

// ── Post-match advancement ──────────────────────────────────────────────────
//
// See the file-level note: isMatchFinished/winnerTeamId are inferred from
// call sites, not from knockout_match.dart directly.

export function isMatchFinished(m: KnockoutMatch): boolean {
  return (m.status === 'completed' || m.status === 'played') && m.homeScore != null && m.awayScore != null;
}

export function winnerTeamId(m: KnockoutMatch): string | null {
  if (m.homeScore == null || m.awayScore == null) return null;
  if (m.homeScore > m.awayScore) return m.homeTeamId;
  if (m.awayScore > m.homeScore) return m.awayTeamId;
  return m.tiebreakWinnerTeamId;
}

/// Automatic advancement after a KO match is confirmed. Handles: Play-off
/// two-legged ties, and single-match R32/R16/QF/SF/Final advancement plus
/// semi-final loser -> 3rd place placement.
export function processMatchResult({
  completedMatch,
  allMatches,
}: {
  completedMatch: KnockoutMatch;
  allMatches: KnockoutMatch[];
}): KnockoutMatch[] {
  if (!isMatchFinished(completedMatch)) return allMatches;

  // Two-legged Play-off aggregate handling (UCL Swiss).
  if (completedMatch.roundName === 'Play-off') {
    if (!completedMatch.isSecondLeg) return allMatches;

    const hId = completedMatch.homeTeamId;
    const aId = completedMatch.awayTeamId;
    if (hId == null || aId == null) return allMatches;

    const nextId = completedMatch.nextMatchId;
    if (nextId == null) return allMatches;

    const tieKey = pairKey(hId, aId);

    const firstLeg = allMatches.find(
      (m) =>
        m.roundName === 'Play-off' &&
        !m.isSecondLeg &&
        m.nextMatchId === nextId &&
        m.homeTeamId != null &&
        m.awayTeamId != null &&
        pairKey(m.homeTeamId, m.awayTeamId) === tieKey,
    );

    if (!firstLeg || !isMatchFinished(firstLeg)) return allMatches;

    const totals: Record<string, number> = { [hId]: 0, [aId]: 0 };
    const add = (m: KnockoutMatch) => {
      const home = m.homeTeamId as string;
      const away = m.awayTeamId as string;
      totals[home] = (totals[home] ?? 0) + (m.homeScore as number);
      totals[away] = (totals[away] ?? 0) + (m.awayScore as number);
    };
    add(firstLeg);
    add(completedMatch);

    const hTot = totals[hId] ?? 0;
    const aTot = totals[aId] ?? 0;

    let winner: string | null;
    if (hTot > aTot) winner = hId;
    else if (aTot > hTot) winner = aId;
    else winner = completedMatch.tiebreakWinnerTeamId;

    if (winner == null) return allMatches;

    return allMatches.map((m) => {
      if (m.id !== nextId) return m;

      const nextHome = m.homeTeamId;
      const nextAway = m.awayTeamId;

      if (nextHome == null && nextAway != null) return { ...m, homeTeamId: winner };
      if (nextAway == null && nextHome != null) return { ...m, awayTeamId: winner };
      if (nextHome == null && nextAway == null) return { ...m, homeTeamId: winner };
      if (nextAway !== winner) return { ...m, awayTeamId: winner };
      return m;
    });
  }

  // Standard single-match advancement for R32/R16/QF/SF/Final.
  const winner = winnerTeamId(completedMatch);
  if (winner == null) return allMatches;

  const loser = winner === completedMatch.homeTeamId ? completedMatch.awayTeamId : completedMatch.homeTeamId;

  let updated = allMatches;

  if (completedMatch.nextMatchId != null) {
    updated = advanceWinnerToNext(completedMatch, winner, updated);
  }

  if (loser != null && completedMatch.roundName === 'Semi Finals' && completedMatch.loserGoesToMatchId != null) {
    updated = placeLoserToThirdPlace(completedMatch, loser, updated);
  }

  return updated;
}
