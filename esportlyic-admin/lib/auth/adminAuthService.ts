// lib/auth/adminAuthService.ts
//
// Server-only admin authorization. This is the web equivalent of the
// mobile app's AppAdminsService, but SERVER-ENFORCED rather than a
// client-side listener — every check here runs against the Admin SDK,
// which is not subject to firestore.rules and cannot be spoofed by a
// tampered client.
//
// Source of truth (confirmed, matches firestore.rules exactly):
//   - isSuperAdmin(): exactly one hardcoded UID.
//   - isPricingAdmin(): the super admin UID, OR any UID listed in
//     app/admins.pricingAdmins[] that looks like a real Firebase UID.
//
// The super admin UID below is the ONLY one in use. A second UID
// (a0JDUelQW3TEyoXTm4ESuGi7ndq1) previously appeared in some mobile
// screens and one Firestore rule — it has been confirmed dead and must
// never be referenced anywhere in this codebase.

import 'server-only';

import { cookies } from 'next/headers';
import { adminAuth, adminDb } from '@/lib/firebase-admin';

export const SUPER_ADMIN_UID = 'QhYeBpvAoRV6j0xGigHkBth4qIG3';

const SESSION_COOKIE_NAME = 'nomad_admin_session';

export interface AdminIdentity {
  uid: string;
  email: string | null;
  isSuperAdmin: boolean;
  /**
   * True for the super admin OR anyone listed in app/admins.pricingAdmins[].
   * This is the same boolean the mobile app calls "isPricingAdmin" —
   * kept under that name in Firestore/rules for backward compatibility,
   * but referred to as "platform admin" in this codebase since it now
   * gates far more than pricing.
   */
  isPlatformAdmin: boolean;
}

/** Mirrors AppAdminsService._looksLikeFirebaseUid — never trust a short/share id as an admin. */
function looksLikeFirebaseUid(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 20;
}

async function fetchPricingAdminUids(): Promise<Set<string>> {
  const snap = await adminDb.collection('app').doc('admins').get();
  if (!snap.exists) return new Set<string>();

  const data = snap.data() ?? {};
  const list = data.pricingAdmins;
  if (!Array.isArray(list)) return new Set<string>();

  return new Set(list.filter(looksLikeFirebaseUid).map((uid) => uid.trim()));
}

/**
 * Verifies a Firebase session cookie and resolves full admin identity.
 * Returns null if the cookie is missing, invalid, expired, or revoked.
 */
export async function getAdminIdentityFromSessionCookie(
  sessionCookie: string | undefined,
): Promise<AdminIdentity | null> {
  if (!sessionCookie) return null;

  try {
    const decoded = await adminAuth.verifySessionCookie(sessionCookie, true);
    const uid = decoded.uid;
    const isSuperAdmin = uid === SUPER_ADMIN_UID;

    if (isSuperAdmin) {
      return {
        uid,
        email: decoded.email ?? null,
        isSuperAdmin: true,
        isPlatformAdmin: true,
      };
    }

    const pricingAdmins = await fetchPricingAdminUids();
    const isPlatformAdmin = pricingAdmins.has(uid);

    return {
      uid,
      email: decoded.email ?? null,
      isSuperAdmin: false,
      isPlatformAdmin,
    };
  } catch {
    return null;
  }
}

/** Convenience helper for Server Components / Route Handlers: reads the cookie jar directly. */
export async function getCurrentAdminIdentity(): Promise<AdminIdentity | null> {
  const cookieStore = cookies();
  const sessionCookie = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  return getAdminIdentityFromSessionCookie(sessionCookie);
}

export { SESSION_COOKIE_NAME };
