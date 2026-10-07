// lib/footballHub/footballHubRepository.ts
//
// Client for Football Hub data, same contract as
// lib/features/football_hub/data/football_api_service.dart: every call
// goes through the Worker's /football/* routes (never api-football.com
// directly), with a Firebase ID token the Worker verifies.

import { auth } from '@/lib/firebase';
import { footballHubUrls } from './footballHubConfig';
import {
  FootballFixture,
  parseFixture,
  FootballStandingsTable,
  parseStandingsEntry,
  FootballLeagueInfo,
  parseLeagueInfo,
  FootballSquadPlayer,
  parseSquadPlayer,
  FootballPlayerProfile,
  parsePlayerProfile,
  FootballMatchEvent,
  parseMatchEvent,
  FootballNewsArticle,
  parseNewsArticle,
} from './types';

async function requireIdToken(): Promise<string> {
  const user = auth.currentUser;
  if (!user) throw new Error('Please sign in and try again.');
  const token = await user.getIdToken();
  if (!token) throw new Error('Authentication token unavailable. Please try again.');
  return token;
}

async function get(urlBuilder: () => string | null, params: Record<string, string>): Promise<any> {
  const endpoint = urlBuilder();
  if (!endpoint) throw new Error('Football Hub is not configured (NEXT_PUBLIC_WORKER_BASE_URL missing).');

  const idToken = await requireIdToken();
  const query = new URLSearchParams(params);

  const res = await fetch(`${endpoint}?${query.toString()}`, {
    headers: { authorization: `Bearer ${idToken}` },
  });

  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    // worker/src/index.js's _looksLikeProviderRateLimitError sets
    // code: "rate_limited" (and status 429) specifically when the free
    // API-Football/GNews daily quota is exhausted, distinct from any
    // other provider error -- surface a curated, honest message instead
    // of the Worker's raw provider-error text (mirrors
    // FootballApiRateLimitException in football_api_service.dart).
    if (body?.code === 'rate_limited' || res.status === 429) {
      throw new Error("Live football data has reached today's free usage limit. Please check back tomorrow.");
    }
    throw new Error(body?.error || `Football Hub error (${res.status})`);
  }
  return body;
}

function responseList(body: any): any[] {
  return Array.isArray(body?.response) ? body.response : [];
}

export async function getFixturesByDate(date: string, leagueId?: number): Promise<FootballFixture[]> {
  const params: Record<string, string> = { date };
  if (leagueId) params.league = String(leagueId);
  const body = await get(footballHubUrls.fixtures, params);
  return responseList(body).map(parseFixture);
}

export async function getFixturesForTeam(
  teamId: number,
  opts: { season?: number; next?: number; last?: number } = {},
): Promise<FootballFixture[]> {
  const params: Record<string, string> = { team: String(teamId) };
  if (opts.season) params.season = String(opts.season);
  if (opts.next) params.next = String(opts.next);
  if (opts.last) params.last = String(opts.last);
  const body = await get(footballHubUrls.fixtures, params);
  return responseList(body).map(parseFixture);
}

export async function getFixtureById(fixtureId: number): Promise<FootballFixture | null> {
  const body = await get(footballHubUrls.fixtures, { id: String(fixtureId) });
  const list = responseList(body);
  return list.length ? parseFixture(list[0]) : null;
}

export async function getFixtureEvents(fixtureId: number): Promise<FootballMatchEvent[]> {
  const body = await get(footballHubUrls.fixtureEvents, { fixture: String(fixtureId) });
  return responseList(body).map(parseMatchEvent);
}

export async function getStandings(leagueId: number, season: number): Promise<FootballStandingsTable | null> {
  const body = await get(footballHubUrls.standings, { league: String(leagueId), season: String(season) });
  const list = responseList(body);
  return list.length ? parseStandingsEntry(list[0]) : null;
}

export async function searchLeagues(search: string): Promise<FootballLeagueInfo[]> {
  const body = await get(footballHubUrls.leagues, { search });
  return responseList(body).map(parseLeagueInfo);
}

export async function getSquad(teamId: number): Promise<FootballSquadPlayer[]> {
  const body = await get(footballHubUrls.squad, { team: String(teamId) });
  const list = responseList(body);
  if (!list.length) return [];
  const players = Array.isArray(list[0]?.players) ? list[0].players : [];
  return players.map(parseSquadPlayer);
}

export async function getPlayer(playerId: number, season: number): Promise<FootballPlayerProfile | null> {
  const body = await get(footballHubUrls.player, { id: String(playerId), season: String(season) });
  const list = responseList(body);
  return list.length ? parsePlayerProfile(list[0]) : null;
}

export async function getFootballNews(query = 'football', max = 10): Promise<FootballNewsArticle[]> {
  const body = await get(footballHubUrls.news, { q: query, max: String(max) });
  const articles = Array.isArray(body?.articles) ? body.articles : [];
  return articles.map(parseNewsArticle);
}

export function currentFootballSeasonGuess(): number {
  const now = new Date();
  const month = now.getMonth() + 1;
  return month >= 7 ? now.getFullYear() : now.getFullYear() - 1;
}

export const POPULAR_LEAGUES = [
  { id: 39, name: 'Premier League' },
  { id: 140, name: 'La Liga' },
  { id: 135, name: 'Serie A' },
  { id: 78, name: 'Bundesliga' },
  { id: 61, name: 'Ligue 1' },
  { id: 2, name: 'Champions League' },
];
