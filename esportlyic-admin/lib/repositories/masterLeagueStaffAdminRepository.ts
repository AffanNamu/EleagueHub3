// lib/repositories/masterLeagueStaffAdminRepository.ts
//
// Admin visibility + revocation for master_leagues/{id}'s staff (owner +
// roles map + staffScopes map) and its staffAuditLog subcollection.
// firestore.rules scopes staffAuditLog reads/writes to the workspace
// owner only (see lib/features/master_leagues/domain/master_league_roles.dart
// and firestore.rules' /staffAuditLog/{entryId} match block) — this
// repository reads/writes through the Admin SDK (adminDb), which bypasses
// those rules entirely, the same way every other module here does.
//
// Writes here use the EXACT same staffAuditLog document shape the mobile/
// web apps write (see MasterLeaguesRepositoryFirebase._staffAuditEntry),
// so an admin-initiated removal shows up correctly in the organizer's own
// Staff screen audit log too — not just this admin panel's audit_logs.

import 'server-only';

import { FieldValue } from 'firebase-admin/firestore';
import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { MasterLeagueStaffMember, MasterLeagueStaffAuditEntry } from '@/types/masterLeagueStaff';

const ROLE_LABELS: Record<string, string> = {
  owner: 'Owner',
  admin: 'Competition Manager',
  result_manager: 'Result Manager',
  moderator: 'Moderator',
};

function roleLabel(storageValue: string): string {
  return ROLE_LABELS[storageValue] ?? storageValue;
}

async function resolveUserProfiles(
  uids: string[],
): Promise<Map<string, { name: string; photo: string }>> {
  const unique = Array.from(new Set(uids.filter(Boolean)));
  const out = new Map<string, { name: string; photo: string }>();
  if (unique.length === 0) return out;

  // getAll() has no realistic size problem at staff-list scale, but chunk
  // defensively (well under Firestore's 500-doc batch ceiling) in case a
  // workspace's audit log has an unusually large number of distinct actors.
  const chunks: string[][] = [];
  for (let i = 0; i < unique.length; i += 300) chunks.push(unique.slice(i, i + 300));

  for (const chunk of chunks) {
    const refs = chunk.map((uid) => adminDb.collection('users').doc(uid));
    const snaps = await adminDb.getAll(...refs);
    snaps.forEach((snap, idx) => {
      const uid = chunk[idx];
      if (!uid) return;
      const data = snap.exists ? snap.data() ?? {} : {};
      const name =
        (typeof data.teamName === 'string' && data.teamName.trim()) ||
        (typeof data.displayName === 'string' && data.displayName.trim()) ||
        (typeof data.username === 'string' && data.username.trim()) ||
        uid;
      const photo =
        (typeof data.profileImageUrl === 'string' && data.profileImageUrl) ||
        (typeof data.teamImageUrl === 'string' && data.teamImageUrl) ||
        (typeof data.photoUrl === 'string' && data.photoUrl) ||
        '';
      out.set(uid, { name, photo });
    });
  }

  return out;
}

export async function listMasterLeagueStaff(
  masterLeagueId: string,
): Promise<MasterLeagueStaffMember[]> {
  const snap = await adminDb.collection('master_leagues').doc(masterLeagueId).get();
  if (!snap.exists) return [];

  const data = snap.data() ?? {};
  const ownerId = (typeof data.ownerId === 'string' && data.ownerId) || data.ownerUid || '';
  const roles =
    typeof data.roles === 'object' && data.roles !== null
      ? (data.roles as Record<string, string>)
      : {};
  const staffScopes =
    typeof data.staffScopes === 'object' && data.staffScopes !== null
      ? (data.staffScopes as Record<string, string[]>)
      : {};

  const profiles = await resolveUserProfiles([ownerId, ...Object.keys(roles)]);
  const members: MasterLeagueStaffMember[] = [];

  if (ownerId) {
    const profile = profiles.get(ownerId);
    members.push({
      uid: ownerId,
      role: 'owner',
      roleLabel: 'Owner',
      isOwner: true,
      scopeLeagueIds: [],
      displayName: profile?.name ?? ownerId,
      photoUrl: profile?.photo ?? '',
    });
  }

  for (const [uid, storageRole] of Object.entries(roles)) {
    if (!uid || uid === ownerId) continue;
    const profile = profiles.get(uid);
    members.push({
      uid,
      role: storageRole,
      roleLabel: roleLabel(storageRole),
      isOwner: false,
      scopeLeagueIds: Array.isArray(staffScopes[uid]) ? staffScopes[uid] : [],
      displayName: profile?.name ?? uid,
      photoUrl: profile?.photo ?? '',
    });
  }

  return members;
}

export async function listMasterLeagueStaffAuditLog(
  masterLeagueId: string,
  limit = 100,
): Promise<MasterLeagueStaffAuditEntry[]> {
  const snap = await adminDb
    .collection('master_leagues')
    .doc(masterLeagueId)
    .collection('staffAuditLog')
    .orderBy('performedAtMs', 'desc')
    .limit(limit)
    .get();

  const raw = snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: typeof data.id === 'string' ? data.id : doc.id,
      action: typeof data.action === 'string' ? data.action : '',
      performedBy: typeof data.performedBy === 'string' ? data.performedBy : '',
      targetUserId: typeof data.targetUserId === 'string' ? data.targetUserId : '',
      targetRole: typeof data.targetRole === 'string' ? data.targetRole : '',
      details: typeof data.details === 'string' ? data.details : '',
      performedAtMs: typeof data.performedAtMs === 'number' ? data.performedAtMs : 0,
    };
  });

  const profiles = await resolveUserProfiles(raw.flatMap((e) => [e.performedBy, e.targetUserId]));

  return raw.map((e) => ({
    ...e,
    performedByName: profiles.get(e.performedBy)?.name ?? e.performedBy,
    targetUserName: profiles.get(e.targetUserId)?.name ?? e.targetUserId,
  }));
}

export class MasterLeagueStaffError extends Error {}

export async function removeMasterLeagueStaff(params: {
  masterLeagueId: string;
  targetUid: string;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection('master_leagues').doc(params.masterLeagueId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new MasterLeagueStaffError('Workspace not found.');
  }

  const data = snap.data() ?? {};
  const ownerId = (typeof data.ownerId === 'string' && data.ownerId) || data.ownerUid || '';
  if (params.targetUid === ownerId) {
    throw new MasterLeagueStaffError('The workspace owner cannot be removed as staff.');
  }

  const roles =
    typeof data.roles === 'object' && data.roles !== null
      ? (data.roles as Record<string, string>)
      : {};
  const previousRole = roles[params.targetUid];
  if (!previousRole) {
    throw new MasterLeagueStaffError('This user is not a staff member of this workspace.');
  }

  await ref.update({
    [`roles.${params.targetUid}`]: FieldValue.delete(),
    [`staffScopes.${params.targetUid}`]: FieldValue.delete(),
  });

  const auditRef = ref.collection('staffAuditLog').doc();
  await auditRef.set({
    id: auditRef.id,
    masterLeagueId: params.masterLeagueId,
    action: 'staff_removed',
    performedBy: params.actorUid,
    targetUserId: params.targetUid,
    targetRole: previousRole,
    details: 'Removed by platform admin',
    performedAtMs: Date.now(),
  });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'organizer_staff.remove',
    targetType: 'master_league_staff',
    targetId: `${params.masterLeagueId}/${params.targetUid}`,
    summary: `Removed staff member ${params.targetUid} (${roleLabel(previousRole)}) from workspace ${params.masterLeagueId}`,
  });
}
