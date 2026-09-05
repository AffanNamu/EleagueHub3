// types/admin.ts
//
// Client-safe copy of AdminIdentity — mirrors lib/auth/adminAuthService.ts
// exactly (that file is 'server-only' and cannot be imported client-side).

export interface AdminIdentity {
  uid: string;
  email: string | null;
  isSuperAdmin: boolean;
  isPlatformAdmin: boolean;
  isLegacyFullAccess: boolean;
  permissions: string[];
  roleNames: string[];
}
