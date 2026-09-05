// lib/repositories/entitlementAdminRepository.ts
//
// Manual entitlement override — mirrors EXACTLY the custom-claims and
// Firestore write shape the Cloudflare Worker's
// _activateOrganizerProGooglePlay / _setFirebaseCustomClaims use, cross-
// checked directly against index.js. This is the capability flagged as
// intentionally unbuilt in every prior status report: it bypasses
// payment verification entirely, so it stays locked behind the
// superAdminOnly "payments.override_entitlement" permission.
//
// CRITICAL CAVEAT (must be surfaced to the person using this): custom
// claims only take effect the next time the affected user's ID token
// refreshes — Firebase tokens are cached client-side for up to an hour,
// or until the user signs out/in. A grant will not be visible to the
// user immediately.
//
// Claims are always MERGED with whatever the user's existing custom
// claims are (via adminAuth.getUser + spread), matching the Worker's
// `{ ...currentClaims, organizerPro: ... }` pattern exactly — never
// wholesale-replaced, since other systems may rely on other claims this
// code has no knowledge of.

import 'server-only';

import { adminAuth, adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { OrganizerProClaims } from '@/types/user';

export class EntitlementOverrideError extends Error {}

const VALID_PLANS = ['pro', 'elite'];
const VALID_DURATIONS = ['3mo', '6mo', 'yearly'];

export async function getCurrentClaims(userId: string): Promise<OrganizerProClaims> {
  try {
    const userRecord = await adminAuth.getUser(userId);
    const claims = userRecord.customClaims ?? {};
    return {
      organizerPro: claims.organizerPro === true,
      organizerProPlan: typeof claims.organizerProPlan === 'string' ? claims.organizerProPlan : null,
      organizerProDuration: typeof claims.organizerProDuration === 'string' ? claims.organizerProDuration : null,
      organizerProExpiryMs: typeof claims.organizerProExpiryMs === 'number' ? claims.organizerProExpiryMs : null,
    };
  } catch {
    return { organizerPro: false, organizerProPlan: null, organizerProDuration: null, organizerProExpiryMs: null };
  }
}

export async function grantEntitlementOverride(params: {
  userId: string;
  plan: string;
  duration: string;
  expiresAtMs: number;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const { userId, plan, duration, expiresAtMs } = params;

  if (!VALID_PLANS.includes(plan)) {
    throw new EntitlementOverrideError(`Plan must be one of: ${VALID_PLANS.join(', ')}.`);
  }
  if (!VALID_DURATIONS.includes(duration)) {
    throw new EntitlementOverrideError(`Duration must be one of: ${VALID_DURATIONS.join(', ')}.`);
  }
  if (!Number.isFinite(expiresAtMs) || expiresAtMs <= Date.now()) {
    throw new EntitlementOverrideError('Expiry must be a valid future date.');
  }

  let userRecord;
  try {
    userRecord = await adminAuth.getUser(userId);
  } catch {
    throw new EntitlementOverrideError('No Firebase Auth account found for this user.');
  }

  const currentClaims = userRecord.customClaims ?? {};
  const nextClaims = {
    ...currentClaims,
    organizerPro: true,
    organizerProPlan: plan,
    organizerProDuration: duration,
    organizerProExpiryMs: expiresAtMs,
  };

  await adminAuth.setCustomUserClaims(userId, nextClaims);

  const nowMs = Date.now();

  await adminDb.collection('users').doc(userId).set(
    {
      activePlanId: plan,
      activePlanDurationId: duration,
      planPurchasedAtMs: nowMs,
      planExpiresAtMs: expiresAtMs,
      planReceiptId: `admin_override_${nowMs}`,
      // 'manual' is a rules-recognized provider value — mobile screens
      // that branch on planProvider will render this correctly rather
      // than hitting an unrecognized-provider fallback.
      planProvider: 'manual',
      updatedAt: nowMs,
    },
    { merge: true },
  );

  await adminDb
    .collection('users')
    .doc(userId)
    .collection('entitlements')
    .doc('master_league')
    .set(
      {
        active: true,
        plan,
        duration,
        provider: 'manual',
        receiptId: `admin_override_${nowMs}`,
        transactionId: '',
        currency: '',
        amount: 0,
        activatedAtMs: nowMs,
        expiresAtMs,
        updatedAtMs: nowMs,
      },
      { merge: true },
    );

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'entitlement.override.grant',
    targetType: 'user',
    targetId: userId,
    summary: `Manually granted ${plan} (${duration}) to ${userId}, bypassing payment verification. Expires ${new Date(expiresAtMs).toISOString()}.`,
  });
}

export async function revokeEntitlementOverride(params: {
  userId: string;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const { userId } = params;

  let userRecord;
  try {
    userRecord = await adminAuth.getUser(userId);
  } catch {
    throw new EntitlementOverrideError('No Firebase Auth account found for this user.');
  }

  const currentClaims = userRecord.customClaims ?? {};
  const nextClaims = {
    ...currentClaims,
    organizerPro: false,
    organizerProExpiryMs: 0,
  };

  await adminAuth.setCustomUserClaims(userId, nextClaims);

  const nowMs = Date.now();

  await adminDb.collection('users').doc(userId).set(
    { planExpiresAtMs: 0, updatedAt: nowMs },
    { merge: true },
  );

  await adminDb
    .collection('users')
    .doc(userId)
    .collection('entitlements')
    .doc('master_league')
    .set({ active: false, expiresAtMs: 0, updatedAtMs: nowMs }, { merge: true });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'entitlement.override.revoke',
    targetType: 'user',
    targetId: userId,
    summary: `Manually revoked plan entitlement for ${userId}.`,
  });
}
