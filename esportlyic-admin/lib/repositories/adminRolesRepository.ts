// lib/repositories/adminRolesRepository.ts

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import { isAssignablePermissionId } from '@/lib/permissions/permissionRegistry';
import type { AdminRole } from '@/types/adminRole';

const COLLECTION = 'admin_roles';

function toAdminRole(id: string, data: FirebaseFirestore.DocumentData): AdminRole {
  return {
    roleId: id,
    name: data.name ?? '',
    description: data.description ?? '',
    permissions: Array.isArray(data.permissions) ? data.permissions : [],
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
    createdBy: data.createdBy ?? '',
  };
}

export class AdminRoleError extends Error {}

function validatePermissions(permissions: string[]): void {
  if (permissions.length === 0) {
    throw new AdminRoleError('A role must include at least one permission.');
  }
  for (const id of permissions) {
    if (!isAssignablePermissionId(id)) {
      throw new AdminRoleError(`"${id}" is not a valid, assignable permission.`);
    }
  }
}

export async function listRoles(): Promise<AdminRole[]> {
  const snap = await adminDb.collection(COLLECTION).orderBy('createdAtMs', 'desc').get();
  return snap.docs.map((doc) => toAdminRole(doc.id, doc.data()));
}

export async function getRole(roleId: string): Promise<AdminRole | null> {
  const snap = await adminDb.collection(COLLECTION).doc(roleId).get();
  if (!snap.exists) return null;
  return toAdminRole(snap.id, snap.data() ?? {});
}

export async function createRole(params: {
  name: string;
  description: string;
  permissions: string[];
  createdBy: string;
  createdByEmail?: string | null;
}): Promise<AdminRole> {
  const name = params.name.trim();
  if (!name) throw new AdminRoleError('Role name is required.');
  validatePermissions(params.permissions);

  const now = Date.now();
  const ref = adminDb.collection(COLLECTION).doc();

  const role: Omit<AdminRole, 'roleId'> = {
    name,
    description: params.description.trim(),
    permissions: params.permissions,
    createdAtMs: now,
    updatedAtMs: now,
    createdBy: params.createdBy,
  };

  await ref.set(role);

  await recordAuditLog({
    actorUid: params.createdBy,
    actorEmail: params.createdByEmail,
    action: 'role.create',
    targetType: 'admin_role',
    targetId: ref.id,
    summary: `Created role "${name}" with ${params.permissions.length} permission(s)`,
  });

  return { roleId: ref.id, ...role };
}

export async function updateRole(
  roleId: string,
  params: { name: string; description: string; permissions: string[]; actorUid: string; actorEmail?: string | null },
): Promise<void> {
  const name = params.name.trim();
  if (!name) throw new AdminRoleError('Role name is required.');
  validatePermissions(params.permissions);

  const ref = adminDb.collection(COLLECTION).doc(roleId);
  const snap = await ref.get();
  if (!snap.exists) throw new AdminRoleError('Role not found.');

  await ref.update({
    name,
    description: params.description.trim(),
    permissions: params.permissions,
    updatedAtMs: Date.now(),
  });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'role.update',
    targetType: 'admin_role',
    targetId: roleId,
    summary: `Updated role "${name}" — now has ${params.permissions.length} permission(s)`,
  });
}

export async function deleteRole(roleId: string, actor: { uid: string; email?: string | null }): Promise<void> {
  const inUseSnap = await adminDb
    .collection('admin_users')
    .where('roleIds', 'array-contains', roleId)
    .limit(1)
    .get();

  if (!inUseSnap.empty) {
    throw new AdminRoleError(
      'This role is currently assigned to at least one admin. Remove it from them before deleting.',
    );
  }

  const snap = await adminDb.collection(COLLECTION).doc(roleId).get();
  const name = snap.exists ? (snap.data()?.name as string) ?? roleId : roleId;

  await adminDb.collection(COLLECTION).doc(roleId).delete();

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'role.delete',
    targetType: 'admin_role',
    targetId: roleId,
    summary: `Deleted role "${name}"`,
  });
}
