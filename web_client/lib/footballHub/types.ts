// lib/footballHub/types.ts
//
// Mirrors lib/features/football_hub/models/*.dart field-for-field so the
// web and Flutter clients parse the exact same Worker responses
// identically -- same provider, same cache, same shapes, two UIs.

export interface FootballFixture {
  id: number;
  kickoff: Date;
  statusShort: string;
  statusLong: string;
  elapsedMinutes: number | null;
  leagueId: number;
  leagueName: string;
  leagueLogoUrl: string;
  leagueCountry: string;
  round: string;
  season: number;
  homeTeamId: number;
  homeTeamName: string;
  homeTeamLogoUrl: string;
  awayTeamId: number;
  awayTeamName: string;
  awayTeamLogoUrl: string;
  homeGoals: number | null;
  awayGoals: number | null;
}

const LIVE_STATUSES = new Set(['1H', '2H', 'HT', 'ET', 'P', 'BT']);
const FINISHED_STATUSES = new Set(['FT', 'AET', 'PEN']);

export function isLiveFixture(f: FootballFixture): boolean {
  return LIVE_STATUSES.has(f.statusShort);
}
export function isFinishedFixture(f: FootballFixture): boolean {
  return FINISHED_STATUSES.has(f.statusShort);
}
export function isUpcomingFixture(f: FootballFixture): boolean {
  return !isLiveFixture(f) && !isFinishedFixture(f);
}

function toInt(v: unknown): number {
  if (typeof v === 'number') return Math.trunc(v);
  const n = parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) ? n : 0;
}
function toIntOrNull(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = toInt(v);
  return Number.isFinite(n) ? n : null;
}
function toStr(v: unknown): string {
  return (v ?? '').toString();
}

export function parseFixture(json: any): FootballFixture {
  const fixture = json?.fixture ?? {};
  const league = json?.league ?? {};
  const teams = json?.teams ?? {};
  const home = teams.home ?? {};
  const away = teams.away ?? {};
  const goals = json?.goals ?? {};
  const status = fixture.status ?? {};

  let kickoff: Date;
  if (typeof fixture.timestamp === 'number') {
    kickoff = new Date(fixture.timestamp * 1000);
  } else {
    const parsed = new Date(toStr(fixture.date));
    kickoff = isNaN(parsed.getTime()) ? new Date() : parsed;
  }

  return {
    id: toInt(fixture.id),
    kickoff,
    statusShort: toStr(status.short),
    statusLong: toStr(status.long),
    elapsedMinutes: toIntOrNull(status.elapsed),
    leagueId: toInt(league.id),
    leagueName: toStr(league.name),
    leagueLogoUrl: toStr(league.logo),
    leagueCountry: toStr(league.country),
    round: toStr(league.round),
    season: toInt(league.season),
    homeTeamId: toInt(home.id),
    homeTeamName: toStr(home.name),
    homeTeamLogoUrl: toStr(home.logo),
    awayTeamId: toInt(away.id),
    awayTeamName: toStr(away.name),
    awayTeamLogoUrl: toStr(away.logo),
    homeGoals: toIntOrNull(goals.home),
    awayGoals: toIntOrNull(goals.away),
  };
}

export interface FootballStandingRow {
  rank: number;
  teamId: number;
  teamName: string;
  teamLogoUrl: string;
  points: number;
  goalsDiff: number;
  played: number;
  win: number;
  draw: number;
  lose: number;
}

export interface FootballStandingsTable {
  leagueId: number;
  leagueName: string;
  leagueLogoUrl: string;
  season: number;
  groups: FootballStandingRow[][];
}

export function parseStandingsEntry(json: any): FootballStandingsTable | null {
  const league = json?.league;
  if (!league) return null;

  const groups: FootballStandingRow[][] = [];
  const standingsRaw = league.standings;
  if (Array.isArray(standingsRaw)) {
    for (const group of standingsRaw) {
      if (!Array.isArray(group)) continue;
      groups.push(
        group.map((row: any) => {
          const team = row?.team ?? {};
          const all = row?.all ?? {};
          return {
            rank: toInt(row?.rank),
            teamId: toInt(team.id),
            teamName: toStr(team.name),
            teamLogoUrl: toStr(team.logo),
            points: toInt(row?.points),
            goalsDiff: toInt(row?.goalsDiff),
            played: toInt(all.played),
            win: toInt(all.win),
            draw: toInt(all.draw),
            lose: toInt(all.lose),
          };
        }),
      );
    }
  }

  return {
    leagueId: toInt(league.id),
    leagueName: toStr(league.name),
    leagueLogoUrl: toStr(league.logo),
    season: toInt(league.season),
    groups,
  };
}

export interface FootballLeagueInfo {
  id: number;
  name: string;
  type: string;
  logoUrl: string;
  countryName: string;
  currentSeason: number;
}

export function parseLeagueInfo(json: any): FootballLeagueInfo {
  const league = json?.league ?? {};
  const country = json?.country ?? {};
  const seasons: any[] = Array.isArray(json?.seasons) ? json.seasons : [];

  let current = seasons.find((s) => s?.current === true);
  if (!current && seasons.length > 0) {
    current = [...seasons].sort((a, b) => toInt(b?.year) - toInt(a?.year))[0];
  }

  return {
    id: toInt(league.id),
    name: toStr(league.name),
    type: toStr(league.type),
    logoUrl: toStr(league.logo),
    countryName: toStr(country.name),
    currentSeason: toInt(current?.year),
  };
}

export interface FootballSquadPlayer {
  id: number;
  name: string;
  age: number;
  number: number | null;
  position: string;
  photoUrl: string;
}

export function parseSquadPlayer(json: any): FootballSquadPlayer {
  return {
    id: toInt(json?.id),
    name: toStr(json?.name),
    age: toInt(json?.age),
    number: toIntOrNull(json?.number),
    position: toStr(json?.position),
    photoUrl: toStr(json?.photo),
  };
}

export interface FootballPlayerProfile {
  id: number;
  name: string;
  photoUrl: string;
  age: number;
  nationality: string;
  primaryPosition: string;
  primaryTeamName: string;
  primaryTeamLogoUrl: string;
  appearances: number;
  goals: number;
  assists: number;
  yellowCards: number;
  redCards: number;
  averageRating: number | null;
}

export function parsePlayerProfile(json: any): FootballPlayerProfile {
  const player = json?.player ?? {};
  const statsList: any[] = Array.isArray(json?.statistics) ? json.statistics : [];
  const birth = player?.birth ?? {};

  let appearances = 0,
    goals = 0,
    assists = 0,
    yellow = 0,
    red = 0;
  const ratings: number[] = [];
  let primaryPosition = '',
    primaryTeamName = '',
    primaryTeamLogoUrl = '';

  statsList.forEach((s, i) => {
    const games = s?.games ?? {};
    const goalsMap = s?.goals ?? {};
    const cards = s?.cards ?? {};
    const team = s?.team ?? {};

    appearances += toInt(games.appearences);
    goals += toInt(goalsMap.total);
    assists += toInt(goalsMap.assists);
    yellow += toInt(cards.yellow);
    red += toInt(cards.red);

    const rating = parseFloat(toStr(games.rating));
    if (!isNaN(rating)) ratings.push(rating);

    if (i === 0) {
      primaryPosition = toStr(games.position);
      primaryTeamName = toStr(team.name);
      primaryTeamLogoUrl = toStr(team.logo);
    }
  });

  return {
    id: toInt(player.id),
    name: toStr(player.name),
    photoUrl: toStr(player.photo),
    age: toInt(player.age),
    nationality: toStr(player.nationality) || toStr(birth.country),
    primaryPosition,
    primaryTeamName,
    primaryTeamLogoUrl,
    appearances,
    goals,
    assists,
    yellowCards: yellow,
    redCards: red,
    averageRating: ratings.length ? ratings.reduce((a, b) => a + b, 0) / ratings.length : null,
  };
}

export interface FootballMatchEvent {
  minute: number;
  extraMinute: number | null;
  type: string;
  detail: string;
  teamName: string;
  playerName: string;
  assistName: string | null;
}

export function parseMatchEvent(json: any): FootballMatchEvent {
  const time = json?.time ?? {};
  const team = json?.team ?? {};
  const player = json?.player ?? {};
  const assist = json?.assist ?? {};
  const assistName = toStr(assist.name);

  return {
    minute: toInt(time.elapsed),
    extraMinute: toIntOrNull(time.extra),
    type: toStr(json?.type),
    detail: toStr(json?.detail),
    teamName: toStr(team.name),
    playerName: toStr(player.name),
    assistName: assistName || null,
  };
}

// GNews's native article shape, parsed directly -- same convention as
// every other type in this file (one Worker response, two clients, no
// server-side re-normalization).
export interface FootballNewsArticle {
  title: string;
  description: string;
  url: string;
  imageUrl: string;
  sourceName: string;
  publishedAt: Date | null;
}

export function parseNewsArticle(json: any): FootballNewsArticle {
  const source = json?.source ?? {};
  const publishedRaw = toStr(json?.publishedAt);
  const parsed = publishedRaw ? new Date(publishedRaw) : null;

  return {
    title: toStr(json?.title),
    description: toStr(json?.description),
    url: toStr(json?.url),
    imageUrl: toStr(json?.image),
    sourceName: toStr(source.name),
    publishedAt: parsed && !isNaN(parsed.getTime()) ? parsed : null,
  };
}
