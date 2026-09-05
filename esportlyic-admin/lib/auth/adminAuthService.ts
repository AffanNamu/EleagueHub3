// lib/auth/adminAuthService.ts
//
// Server-only admin authorization AND permission resolution.
//
// Three tiers, resolved in order:
//   1. Super admin (QhYeBpvAoRV6j0xGigHkBth4qIG3) — every permission,
//      always. Cannot be delegated or removed.
//   2. Legacy full access — anyone in app/admins.pricingAdmins[] who does
//      NOT have a narrower admin_users role assignment. Preserves exact
//      current behavior for every admin who existed before this system:
//      they keep full access, nothing breaks.
//   3. Granular role-based — anyone with an admin_users/{uid} doc gets
//      the union of permissions from their assigned admin_roles docs.
//      This is the new, real delegation system.
//
// A uid can be in BOTH (2) and (3) — legacy full access always wins in
// that case, since it's a superset of any role's permissions.

import 'server-only';

import { cookies } from 'next/headers';
import { adminAuth, adminDb } from '@/lib/firebase-admin';
import { getRole } from '@/lib/repositories/adminRolesRepository';

export const SUPER_ADMIN_UID = 'QhYeBpvAoRV6j0xGigHkBth4qIG3';

const SESSION_COOKIE_NAME = 'nomad_admin_session';

export interface AdminIdentity {
  uid: string;
  email: string | null;
  isSuperAdmin: boolean;
  /** Kept for backward compatibility with earlier modules — true if the account has ANY admin access at all. */
  isPlatformAdmin: boolean;
  /** True if access comes from the legacy app/admins.pricingAdmins[] array rather than a granular role. */
  isLegacyFullAccess: boolean;
  /** Resolved permission IDs from all assigned roles. Empty for super admin / legacy (they bypass this check entirely). */
  permissions: string[];
  roleNames: string[];
}

function looksLikeFirebaseUid(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 20;
}

async function fetchLegacyPricingAdminUids(): Promise<Set<string>> {
  const snap = await adminDb.collection('app').doc('admins').get();
  if (!snap.exists) return new Set();
  const list = snap.data()?.pricingAdmins;
  if (!Array.isArray(list)) return new Set();
  return new Set(list.filter(looksLikeFirebaseUid).map((v: string) => v.trim()));
}

async function resolveIdentity(uid: string, email: string | null): Promise<AdminIdentity> {
  if (uid === SUPER_ADMIN_UID) {
    return {
      uid,
      email,
      isSuperAdmin: true,
      isPlatformAdmin: true,
      isLegacyFullAccess: true,
      permissions: [],
      roleNames: ['Super Admin'],
    };
  }

  const legacyUids = await fetchLegacyPricingAdminUids();
  const isLegacyFullAccess = legacyUids.has(uid);

  if (isLegacyFullAccess) {
    return {
      uid,
      email,
      isSuperAdmin: false,
      isPlatformAdmin: true,
      isLegacyFullAccess: true,
      permissions: [],
      roleNames: ['Legacy Full Access'],
    };
  }

  const userDoc = await adminDb.collection('admin_users').doc(uid).get();
  if (!userDoc.exists) {
    return {
      uid,
      email,
      isSuperAdmin: false,
      isPlatformAdmin: false,
      isLegacyFullAccess: false,
      permissions: [],
      roleNames: [],
    };
  }

  const roleIds: string[] = Array.isArray(userDoc.data()?.roleIds) ? userDoc.data()!.roleIds : [];
  const roles = await Promise.all(roleIds.map((id) => getRole(id)));
  const validRoles = roles.filter((r): r is NonNullable<typeof r> => r !== null);

  const permissionSet = new Set<string>();
  for (const role of validRoles) {
    for (const permission of role.permissions) permissionSet.add(permission);
  }

  return {
    uid,
    email,
    isSuperAdmin: false,
    isPlatformAdmin: permissionSet.size > 0,
    isLegacyFullAccess: false,
    permissions: Array.from(permissionSet),
    roleNames: validRoles.map((r) => r.name),
  };
}

export async function getAdminIdentityFromSessionCookie(
  sessionCookie: string | undefined,
): Promise<AdminIdentity | null> {
  if (!sessionCookie) return null;

  try {
    const decoded = await adminAuth.verifySessionCookie(sessionCookie, true);
    return await resolveIdentity(decoded.uid, decoded.email ?? null);
  } catch {
    return null;
  }
}

export async function getCurrentAdminIdentity(): Promise<AdminIdentity | null> {
  const cookieStore = cookies();
  const sessionCookie = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  return getAdminIdentityFromSessionCookie(sessionCookie);
}

export { SESSION_COOKIE_NAME };
