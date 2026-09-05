// lib/repositories/masterLeaguesAdminRepository.ts
//
// Server-only reads of master_leagues and users, scoped to what the
// Verification review panel needs for context. Replicates
// MasterLeague.fromMap's defensive owner-id fallback chain
// (ownerId -> ownerUid) so legacy documents are read correctly.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import type { MasterLeagueSummary, OwnerProfileSummary } from '@/types/verification';

export async function getMasterLeagueSummary(
  masterLeagueId: string,
): Promise<MasterLeagueSummary | null> {
  const snap = await adminDb.collection('master_leagues').doc(masterLeagueId).get();
  if (!snap.exists) return null;

  const data = snap.data() ?? {};

  return {
    id: snap.id,
    name: typeof data.name === 'string' ? data.name : '',
    ownerId: typeof data.ownerId === 'string' && data.ownerId ? data.ownerId : (data.ownerUid ?? ''),
    plan: (data.plan as MasterLeagueSummary['plan']) ?? 'basic',
    logoUrl: typeof data.logoUrl === 'string' ? data.logoUrl : '',
    bannerUrl: typeof data.bannerUrl === 'string' ? data.bannerUrl : '',
    verificationStatus: (data.verificationStatus as MasterLeagueSummary['verificationStatus']) ?? 'none',
    verifiedBadge: data.verifiedBadge === true,
    verificationExpiresAtMs: typeof data.verificationExpiresAtMs === 'number' ? data.verificationExpiresAtMs : 0,
    totalTournamentsCreated: typeof data.totalTournamentsCreated === 'number' ? data.totalTournamentsCreated : 0,
    totalParticipantsTeams: typeof data.totalParticipantsTeams === 'number' ? data.totalParticipantsTeams : 0,
    followersCount: typeof data.followersCount === 'number' ? data.followersCount : 0,
  };
}

export async function getOwnerProfileSummary(userId: string): Promise<OwnerProfileSummary | null> {
  if (!userId) return null;

  const snap = await adminDb.collection('users').doc(userId).get();
  if (!snap.exists) return null;

  const data = snap.data() ?? {};
  const displayName =
    (typeof data.teamName === 'string' && data.teamName.trim()) ||
    (typeof data.displayName === 'string' && data.displayName.trim()) ||
    (typeof data.username === 'string' && data.username.trim()) ||
    'User';

  const photoUrl =
    (typeof data.profileImageUrl === 'string' && data.profileImageUrl) ||
    (typeof data.teamImageUrl === 'string' && data.teamImageUrl) ||
    (typeof data.photoUrl === 'string' && data.photoUrl) ||
    '';

  return { userId, displayName, photoUrl };
}
