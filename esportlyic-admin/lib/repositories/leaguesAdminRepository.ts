// lib/repositories/leaguesAdminRepository.ts
//
// UPDATED: added updateLeague()/deleteLeague(). Edit is deliberately
// scoped to LeagueInput's fields (see types/league.ts) -- format,
// maxTeams, masterLeagueId, and ownership are excluded as unsafe to
// hand-edit on a league that may already have matches/teams/a bracket.
// deleteLeague uses Firestore's recursiveDelete so subcollections
// (matches, knockout, teams, memberships, competitionRules,
// pointAdjustments, etc.) don't get orphaned.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import { leagueFormatFromIndex, type League, type LeagueInput } from '@/types/league';

const COLLECTION = 'leagues';

export class LeagueAdminError extends Error {}

function toLeague(id: string, data: FirebaseFirestore.DocumentData): League {
  const memberIds = Array.isArray(data.memberIds) ? data.memberIds : [];

  return {
    id,
    name: data.name ?? '',
    description: typeof data.description === 'string' ? data.description : '',
    format: leagueFormatFromIndex(typeof data.format === 'number' ? data.format : 0),
    organizerUid: data.organizerUid ?? data.organizerUserId ?? '',
    ownerUid: data.ownerUid ?? data.ownerId ?? '',
    masterLeagueId: data.masterLeagueId ?? '',
    isPrivate: data.isPrivate === true,
    maxTeams: typeof data.maxTeams === 'number' ? data.maxTeams : 0,
    memberCount: memberIds.length,
    footballCategory: data.footballCategory ?? '',
    couponsEnabled: data.couponsEnabled === true,
    region: typeof data.region === 'string' ? data.region : '',
    season: typeof data.season === 'string' ? data.season : '',
    leagueImageUrl: typeof data.leagueImageUrl === 'string' ? data.leagueImageUrl : '',
    sponsorImageUrl: typeof data.sponsorImageUrl === 'string' ? data.sponsorImageUrl : '',
    createdAtMs:
      data.createdAt && typeof data.createdAt.toMillis === 'function' ? data.createdAt.toMillis() : 0,
  };
}

function validate(input: LeagueInput): void {
  if (!input.name.trim()) throw new LeagueAdminError('Name is required.');
  if (input.name.length > 100) throw new LeagueAdminError('Name must be 100 characters or fewer.');
  if (input.description.length > 2000) {
    throw new LeagueAdminError('Description must be 2000 characters or fewer.');
  }
}

export async function listLeagues(params: { search?: string; limit?: number } = {}): Promise<League[]> {
  const { search, limit = 50 } = params;

  let query: FirebaseFirestore.Query = adminDb.collection(COLLECTION);

  const term = search?.trim();
  if (term) {
    query = query.orderBy('name').startAt(term).endAt(`${term}\uf8ff`).limit(limit);
  } else {
    query = query.orderBy('createdAt', 'desc').limit(limit);
  }

  const snap = await query.get();
  return snap.docs.map((doc) => toLeague(doc.id, doc.data()));
}

export async function getLeague(id: string): Promise<League | null> {
  const snap = await adminDb.collection(COLLECTION).doc(id).get();
  if (!snap.exists) return null;
  return toLeague(snap.id, snap.data() ?? {});
}

export async function updateLeague(
  id: string,
  input: LeagueInput,
  actor: { uid: string; email?: string | null },
): Promise<League> {
  validate(input);

  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) throw new LeagueAdminError('League not found.');

  const data = {
    name: input.name.trim(),
    description: input.description.trim(),
    isPrivate: input.isPrivate,
    region: input.region.trim(),
    season: input.season.trim(),
    leagueImageUrl: input.leagueImageUrl.trim(),
    sponsorImageUrl: input.sponsorImageUrl.trim(),
    updatedAtMs: Date.now(),
  };

  await ref.update(data);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'league.update',
    targetType: 'league',
    targetId: id,
    summary: `Updated league "${data.name}"`,
  });

  return toLeague(id, { ...existing.data(), ...data });
}

export async function deleteLeague(id: string, actor: { uid: string; email?: string | null }): Promise<void> {
  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) throw new LeagueAdminError('League not found.');

  const name = (existing.data()?.name as string) || id;

  await adminDb.recursiveDelete(ref);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'league.delete',
    targetType: 'league',
    targetId: id,
    summary: `Deleted league "${name}" and all its matches/teams/subcollections`,
  });
}
