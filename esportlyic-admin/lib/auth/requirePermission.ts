// lib/auth/requirePermission.ts
//
// Shared permission-check used by every API route and Server Component.
// Super admin and legacy-full-access bypass the specific permission
// check entirely (they have everything); everyone else needs the exact
// permission ID in their resolved set.

import type { AdminIdentity } from '@/types/admin';

export function hasPermission(identity: AdminIdentity | null, permissionId: string): boolean {
  if (!identity) return false;
  if (identity.isSuperAdmin || identity.isLegacyFullAccess) return true;
  return identity.permissions.includes(permissionId);
}
