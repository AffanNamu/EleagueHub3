// lib/repositories/organizersAdminRepository.ts
//
// UPDATED: added updateOrganizer()/deleteOrganizer(). Edit is scoped to
// OrganizerInput's fields (see types/organizer.ts) -- ownership, staff,
// verification, and analytics fields are excluded. plan is genuinely
// the workspace's own authoritative field per firestore.rules (not a
// display-only cache), so editing it here really does change what the
// workspace can do. deleteOrganizer uses recursiveDelete so subcollections
// (disciplineActions, staffAuditLog, organizer_feed items scoped here,
// etc.) don't get orphaned.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { Organizer, OrganizerInput } from '@/types/organizer';

const COLLECTION = 'master_leagues';

export class OrganizerAdminError extends Error {}

function toOrganizer(id: string, data: FirebaseFirestore.DocumentData): Organizer {
  return {
    id,
    name: data.name ?? '',
    ownerId: (typeof data.ownerId === 'string' && data.ownerId) || data.ownerUid || '',
    memberIds: Array.isArray(data.memberIds) ? data.memberIds : [],
    roles: typeof data.roles === 'object' && data.roles !== null ? data.roles : {},
    plan: (data.plan as Organizer['plan']) ?? 'basic',
    purchaseStatus: data.purchaseStatus ?? '',
    bannerUrl: data.bannerUrl ?? '',
    logoUrl: data.logoUrl ?? '',
    bio: data.bio ?? '',
    badge: data.badge ?? '',
    socialLinks: typeof data.socialLinks === 'object' && data.socialLinks !== null ? data.socialLinks : {},
    country: data.country ?? '',
    usernameLower: data.usernameLower ?? '',
    verificationStatus: (data.verificationStatus as Organizer['verificationStatus']) ?? 'none',
    verifiedBadge: data.verifiedBadge === true,
    verificationExpiresAtMs: typeof data.verificationExpiresAtMs === 'number' ? data.verificationExpiresAtMs : 0,
    totalTournamentsCreated: typeof data.totalTournamentsCreated === 'number' ? data.totalTournamentsCreated : 0,
    totalParticipantsTeams: typeof data.totalParticipantsTeams === 'number' ? data.totalParticipantsTeams : 0,
    totalMatches: typeof data.totalMatches === 'number' ? data.totalMatches : 0,
    followersCount: typeof data.followersCount === 'number' ? data.followersCount : 0,
    createdAtMs:
      data.createdAt && typeof data.createdAt.toMillis === 'function' ? data.createdAt.toMillis() : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

export async function listOrganizers(params: { search?: string; limit?: number } = {}): Promise<Organizer[]> {
  const { search, limit = 50 } = params;

  let query: FirebaseFirestore.Query = adminDb.collection('master_leagues');

  const term = search?.trim();
  if (term) {
    query = query.orderBy('name').startAt(term).endAt(`${term}\uf8ff`).limit(limit);
  } else {
    query = query.orderBy('createdAt', 'desc').limit(limit);
  }

  const snap = await query.get();
  return snap.docs.map((doc) => toOrganizer(doc.id, doc.data()));
}

export async function getOrganizer(id: string): Promise<Organizer | null> {
  const snap = await adminDb.collection('master_leagues').doc(id).get();
  if (!snap.exists) return null;
  return toOrganizer(snap.id, snap.data() ?? {});
}

function validate(input: OrganizerInput): void {
  if (!input.name || !input.name.trim()) {
    throw new OrganizerAdminError('Name is required.');
  }
  if (input.name.length > 100) {
    throw new OrganizerAdminError('Name must be 100 characters or fewer.');
  }
  if (input.bio && input.bio.length > 2000) {
    throw new OrganizerAdminError('Bio must be 2000 characters or fewer.');
  }
  if (!['basic', 'pro', 'elite'].includes(input.plan)) {
    throw new OrganizerAdminError('Invalid plan.');
  }
}

export async function updateOrganizer(
  id: string,
  input: OrganizerInput,
  actor: { uid: string; email?: string | null }
): Promise<Organizer> {
  validate(input);

  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) {
    throw new OrganizerAdminError('Organizer workspace not found.');
  }

  const data = {
    name: input.name.trim(),
    plan: input.plan,
    bio: (input.bio ?? '').trim(),
    logoUrl: (input.logoUrl ?? '').trim(),
    bannerUrl: (input.bannerUrl ?? '').trim(),
    country: (input.country ?? '').trim(),
    socialLinks: input.socialLinks ?? {},
    updatedAtMs: Date.now(),
  };

  await ref.update(data);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'organizer.update',
    targetType: 'master_league',
    targetId: id,
    summary: `Updated organizer workspace "${data.name}"`,
  });

  return toOrganizer(id, { ...existing.data(), ...data });
}

export async function deleteOrganizer(id: string, actor: { uid: string; email?: string | null }): Promise<void> {
  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) {
    throw new OrganizerAdminError('Organizer workspace not found.');
  }
  const name = (existing.data()?.name as string) || id;

  await adminDb.recursiveDelete(ref);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'organizer.delete',
    targetType: 'master_league',
    targetId: id,
    summary: `Deleted organizer workspace "${name}" and all its subcollections`,
  });
}
