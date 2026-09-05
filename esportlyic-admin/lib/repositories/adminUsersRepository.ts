// lib/repositories/adminUsersRepository.ts

import 'server-only';

import { FieldValue } from 'firebase-admin/firestore';
import { adminAuth, adminDb } from '@/lib/firebase-admin';
import { SUPER_ADMIN_UID } from '@/lib/auth/adminAuthService';
import { getRole } from '@/lib/repositories/adminRolesRepository';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { AdminUserRecord } from '@/types/adminRole';

const COLLECTION = 'admin_users';

function looksLikeFirebaseUid(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 20;
}

async function getLegacyPricingAdminUids(): Promise<Set<string>> {
  const snap = await adminDb.collection('app').doc('admins').get();
  if (!snap.exists) return new Set();
  const list = snap.data()?.pricingAdmins;
  if (!Array.isArray(list)) return new Set();
  return new Set(list.filter(looksLikeFirebaseUid).map((v: string) => v.trim()));
}

async function resolveRoleNames(roleIds: string[]): Promise<string[]> {
  const names = await Promise.all(
    roleIds.map(async (id) => {
      const role = await getRole(id);
      return role?.name ?? '(deleted role)';
    }),
  );
  return names;
}

export class AdminUserError extends Error {}

export async function listAdminUsers(): Promise<AdminUserRecord[]> {
  const [docsSnap, legacyUids] = await Promise.all([
    adminDb.collection(COLLECTION).get(),
    getLegacyPricingAdminUids(),
  ]);

  const records: AdminUserRecord[] = [];
  const seenUids = new Set<string>();

  for (const doc of docsSnap.docs) {
    const data = doc.data();
    const roleIds = Array.isArray(data.roleIds) ? data.roleIds : [];
    records.push({
      uid: doc.id,
      email: data.email ?? '',
      roleIds,
      roleNames: await resolveRoleNames(roleIds),
      isLegacyFullAccess: legacyUids.has(doc.id),
      isSuperAdmin: doc.id === SUPER_ADMIN_UID,
      addedAtMs: typeof data.addedAtMs === 'number' ? data.addedAtMs : 0,
      addedBy: data.addedBy ?? '',
    });
    seenUids.add(doc.id);
  }

  for (const uid of legacyUids) {
    if (seenUids.has(uid) || uid === SUPER_ADMIN_UID) continue;
    records.push({
      uid,
      email: '',
      roleIds: [],
      roleNames: [],
      isLegacyFullAccess: true,
      isSuperAdmin: false,
      addedAtMs: 0,
      addedBy: 'legacy',
    });
  }

  if (!records.some((r) => r.uid === SUPER_ADMIN_UID)) {
    records.unshift({
      uid: SUPER_ADMIN_UID,
      email: '',
      roleIds: [],
      roleNames: [],
      isLegacyFullAccess: true,
      isSuperAdmin: true,
      addedAtMs: 0,
      addedBy: '',
    });
  }

  return records.sort((a, b) => (b.isSuperAdmin ? 1 : 0) - (a.isSuperAdmin ? 1 : 0));
}

export async function addAdminUser(params: {
  email: string;
  roleIds: string[];
  grantLegacyPricingAdmin: boolean;
  addedBy: string;
}): Promise<AdminUserRecord> {
  const email = params.email.trim().toLowerCase();
  if (!email) throw new AdminUserError('Email is required.');

  let uid: string;
  try {
    const userRecord = await adminAuth.getUserByEmail(email);
    uid = userRecord.uid;
  } catch {
    throw new AdminUserError(
      'No Firebase account found for that email. The person must sign in to the app at least once before being added as an admin.',
    );
  }

  if (uid === SUPER_ADMIN_UID) {
    throw new AdminUserError('This account is already the Super Admin.');
  }

  for (const roleId of params.roleIds) {
    const role = await getRole(roleId);
    if (!role) throw new AdminUserError(`Role "${roleId}" does not exist.`);
  }

  const now = Date.now();
  await adminDb.collection(COLLECTION).doc(uid).set({
    email,
    roleIds: params.roleIds,
    addedAtMs: now,
    addedBy: params.addedBy,
  });

  if (params.grantLegacyPricingAdmin) {
    await adminDb.collection('app').doc('admins').set(
      { pricingAdmins: FieldValue.arrayUnion(uid) },
      { merge: true },
    );
  }

  await recordAuditLog({
    actorUid: params.addedBy,
    action: 'admin.add',
    targetType: 'admin_user',
    targetId: uid,
    summary: `Added ${email} as admin with ${params.roleIds.length} role(s)${params.grantLegacyPricingAdmin ? ' + legacy mobile access' : ''}`,
  });

  return {
    uid,
    email,
    roleIds: params.roleIds,
    roleNames: await resolveRoleNames(params.roleIds),
    isLegacyFullAccess: params.grantLegacyPricingAdmin,
    isSuperAdmin: false,
    addedAtMs: now,
    addedBy: params.addedBy,
  };
}

export async function updateAdminUser(
  uid: string,
  params: { roleIds: string[]; grantLegacyPricingAdmin: boolean; actorUid: string; actorEmail?: string | null },
): Promise<void> {
  if (uid === SUPER_ADMIN_UID) {
    throw new AdminUserError('The Super Admin cannot be modified.');
  }

  for (const roleId of params.roleIds) {
    const role = await getRole(roleId);
    if (!role) throw new AdminUserError(`Role "${roleId}" does not exist.`);
  }

  const ref = adminDb.collection(COLLECTION).doc(uid);
  const snap = await ref.get();

  if (snap.exists) {
    await ref.update({ roleIds: params.roleIds });
  } else {
    await ref.set({ email: '', roleIds: params.roleIds, addedAtMs: Date.now(), addedBy: '' });
  }

  const adminsRef = adminDb.collection('app').doc('admins');
  if (params.grantLegacyPricingAdmin) {
    await adminsRef.set({ pricingAdmins: FieldValue.arrayUnion(uid) }, { merge: true });
  } else {
    await adminsRef.set({ pricingAdmins: FieldValue.arrayRemove(uid) }, { merge: true });
  }

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'admin.update',
    targetType: 'admin_user',
    targetId: uid,
    summary: `Updated access for ${uid}: ${params.roleIds.length} role(s)${params.grantLegacyPricingAdmin ? ' + legacy mobile access' : ', no legacy mobile access'}`,
  });
}

export async function removeAdminUser(
  uid: string,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  if (uid === SUPER_ADMIN_UID) {
    throw new AdminUserError('The Super Admin cannot be removed.');
  }

  await adminDb.collection(COLLECTION).doc(uid).delete();
  await adminDb.collection('app').doc('admins').set(
    { pricingAdmins: FieldValue.arrayRemove(uid) },
    { merge: true },
  );

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'admin.remove',
    targetType: 'admin_user',
    targetId: uid,
    summary: `Removed admin access for ${uid}`,
  });
}
