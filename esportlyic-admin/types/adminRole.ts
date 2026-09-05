// types/adminRole.ts

export interface AdminRole {
  roleId: string;
  name: string;
  description: string;
  permissions: string[];
  createdAtMs: number;
  updatedAtMs: number;
  createdBy: string;
}

export interface AdminUserRecord {
  uid: string;
  email: string;
  roleIds: string[];
  roleNames: string[];
  /** True if this uid is in the legacy app/admins.pricingAdmins[] array (full mobile + web access). */
  isLegacyFullAccess: boolean;
  isSuperAdmin: boolean;
  addedAtMs: number;
  addedBy: string;
}
