// lib/repositories/organizersAdminRepository.ts

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import type { Organizer } from '@/types/organizer';

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
