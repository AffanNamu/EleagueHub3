// lib/repositories/leaguesAdminRepository.ts

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { leagueFormatFromIndex, type League } from '@/types/league';

function toLeague(id: string, data: FirebaseFirestore.DocumentData): League {
  const memberIds = Array.isArray(data.memberIds) ? data.memberIds : [];

  return {
    id,
    name: data.name ?? '',
    format: leagueFormatFromIndex(typeof data.format === 'number' ? data.format : 0),
    organizerUid: data.organizerUid ?? data.organizerUserId ?? '',
    ownerUid: data.ownerUid ?? data.ownerId ?? '',
    masterLeagueId: data.masterLeagueId ?? '',
    isPrivate: data.isPrivate === true,
    maxTeams: typeof data.maxTeams === 'number' ? data.maxTeams : 0,
    memberCount: memberIds.length,
    footballCategory: data.footballCategory ?? '',
    couponsEnabled: data.couponsEnabled === true,
    createdAtMs:
      data.createdAt && typeof data.createdAt.toMillis === 'function' ? data.createdAt.toMillis() : 0,
  };
}

export async function listLeagues(params: { search?: string; limit?: number } = {}): Promise<League[]> {
  const { search, limit = 50 } = params;

  let query: FirebaseFirestore.Query = adminDb.collection('leagues');

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
  const snap = await adminDb.collection('leagues').doc(id).get();
  if (!snap.exists) return null;
  return toLeague(snap.id, snap.data() ?? {});
}
