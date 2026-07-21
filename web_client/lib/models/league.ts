import { FootballCategory, footballCategoryFromStorage } from './footballCategory';
import { LeagueFormat, leagueFormatFromInt } from './leagueFormat';

export type LeaguePrivacy = 'public' | 'private';
export type LeagueRole = 'organizer' | 'member';

export interface LeagueData {
  id: string;
  name: string;
  masterLeagueId: string;
  description: string;
  leagueImageUrl: string;
  sponsorImageUrl: string;
  viewerCapacity: number;
  couponsEnabled: boolean;
  couponDiscountPercent: number;
  couponCount: number;
  homeAwayEnabled: boolean;
  footballCategory: FootballCategory;
  format: LeagueFormat;
  worldCupFormat: number;
  privacy: LeaguePrivacy;
  region: string;
  maxTeams: number;
  season: string;
  organizerUid: string;
  organizerUserId: string;
  code: string;
  qrPayloadOverride: string;
  updatedAtMs: number;
  version: number;
}

function stringFromAny(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function intFromAny(v: unknown, fallback = 0): number {
  if (v === null || v === undefined) return fallback;
  if (typeof v === 'number') return Math.trunc(v);
  if (typeof v === 'string') {
    const n = parseInt(v.trim(), 10);
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}

function boolFromAny(v: unknown, fallback = false): boolean {
  if (v === null || v === undefined) return fallback;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v === 1;
  if (typeof v === 'string') {
    const s = v.trim().toLowerCase();
    if (s === 'true' || s === '1' || s === 'yes') return true;
    if (s === 'false' || s === '0' || s === 'no') return false;
  }
  return fallback;
}

export function leagueFromRemoteMap(map: Record<string, unknown>): LeagueData {
  const leagueImageUrl =
    stringFromAny(map.leagueImageUrl).trim() ||
    stringFromAny(map.leagueImage).trim() ||
    stringFromAny(map.imageUrl).trim() ||
    stringFromAny(map.logoUrl);

  const sponsorImageUrl = stringFromAny(map.sponsorImageUrl).trim();

  const viewerCapacity = intFromAny(map.viewerCapacity ?? map.viewerCount, 0);

  const id = stringFromAny(map.id) || stringFromAny(map.leagueId);
  const name = stringFromAny(map.name) || stringFromAny(map.leagueName);
  const masterLeagueId = stringFromAny(map.masterLeagueId).trim();

  let organizerUid = stringFromAny(map.organizerUid).trim();
  const organizerUserId =
    stringFromAny(map.organizerUserId) || stringFromAny(map.ownerId) || stringFromAny(map.organizerId);

  if (!organizerUid && organizerUserId.trim().length > 20) {
    organizerUid = organizerUserId.trim();
  }

  const isPrivate = boolFromAny(map.isPrivate, false);
  const footballCategory = footballCategoryFromStorage(
    typeof map.footballCategory === 'string' ? map.footballCategory : undefined,
  );
  const format = leagueFormatFromInt(typeof map.format === 'number' ? map.format : Number(map.format ?? 0));

  // Extract World Cup Format from settings or fallback to maxTeams
  const settings = (map.settings as Record<string, any>) || {};
  const wcFormatStr = stringFromAny(settings.worldCupFormatStr);
  const maxTeams = intFromAny(map.maxTeams, 20);
  const worldCupFormat = wcFormatStr.includes('48') || maxTeams === 48 ? 48 : 32;

  return {
    id,
    name,
    masterLeagueId,
    description: stringFromAny(map.description),
    leagueImageUrl,
    sponsorImageUrl,
    viewerCapacity,
    couponsEnabled: boolFromAny(map.couponsEnabled, false),
    couponDiscountPercent: intFromAny(map.couponDiscountPercent, 0),
    couponCount: intFromAny(map.couponCount, 0),
    homeAwayEnabled: boolFromAny(map.homeAwayEnabled, false),
    footballCategory,
    format,
    worldCupFormat,
    privacy: isPrivate ? 'private' : 'public',
    region: stringFromAny(map.region) || 'Global',
    maxTeams,
    season: stringFromAny(map.season) || '2026',
    organizerUid,
    organizerUserId,
    code: stringFromAny(map.code),
    qrPayloadOverride: stringFromAny(map.qrPayload),
    updatedAtMs: intFromAny(map.updatedAtMs, 0),
    version: intFromAny(map.version, 1),
  };
}

export function leagueIsInsideMasterLeague(l: LeagueData): boolean {
  return l.masterLeagueId.trim().length > 0;
}

export function leagueHasViewerCapacity(l: LeagueData): boolean {
  return l.viewerCapacity > 0;
}

export function leagueQrPayload(l: LeagueData): string {
  const override = l.qrPayloadOverride.trim();
  if (override) return override;

  const code = l.code.trim();
  const id = l.id.trim();
  if (!code) return `https://esportlyic.web.app/join?id=${id}`;
  return `https://esportlyic.web.app/join?code=${code}&id=${id}`;
}

export interface Membership {
  id: string;
  leagueId: string;
  userId: string;
  teamId: string | null;
  role: LeagueRole;
  updatedAtMs: number;
  version: number;
}

export function membershipFromRemoteMap(map: Record<string, unknown>): Membership {
  const roleIdx = intFromAny(map.role, 1);
  return {
    id: stringFromAny(map.id),
    leagueId: stringFromAny(map.leagueId),
    userId: stringFromAny(map.userId),
    teamId: typeof map.teamId === 'string' ? map.teamId : null,
    role: roleIdx === 0 ? 'organizer' : 'member',
    updatedAtMs: intFromAny(map.updatedAtMs, 0),
    version: intFromAny(map.version, 1),
  };
}

export function looksLikeFirebaseUid(s: string): boolean {
  return s.trim().length > 20;
}

export function isOwnerForViewer(league: LeagueData, viewerUid: string): boolean {
  const v = viewerUid.trim();
  if (!v) return false;

  const orgUid = league.organizerUid.trim();
  if (orgUid) return orgUid === v;

  const legacy = league.organizerUserId.trim();
  return legacy.length > 0 && legacy === v && looksLikeFirebaseUid(legacy);
}
