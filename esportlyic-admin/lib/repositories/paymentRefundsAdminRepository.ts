// lib/repositories/paymentRefundsAdminRepository.ts
//
// Marks a payments/{id} doc as refunded and, for the two product types
// where reversal is unambiguous (plan_subscription and
// organizer_verification[_renewal] -- see AUTO_REVOKABLE_PRODUCT_TYPES
// in types/payment.ts), optionally reverses the access that payment
// granted on the fulfilled master_leagues/{id} workspace.
//
// IMPORTANT, surfaced to the caller and the UI: this does NOT call any
// payment processor. There is no Flutterwave refund API, App Store
// Server API refund request, or Google Play revoke call anywhere in
// this codebase (confirmed against worker/src/index.js) -- actually
// returning the customer's money still has to happen in the
// Flutterwave dashboard / App Store Connect / Play Console. This tool
// only records the refund and, optionally, revokes the access it
// granted.
//
// Resetting `plan` back to 'basic' is a conservative default: if this
// payment was an upgrade from an already-paid lower tier (e.g.
// pro -> elite), the workspace loses that lower tier too rather than
// stepping back down to it, since reconstructing "what tier were they
// on before this specific payment" would require replaying every prior
// payment for this workspace. Flagged in the UI copy so the admin can
// choose not to revoke, or fix the tier manually via the Organizer edit
// form afterward, when that matters.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import { AUTO_REVOKABLE_PRODUCT_TYPES } from '@/types/payment';

const PAYMENTS_COLLECTION = 'payments';
const MASTER_LEAGUES_COLLECTION = 'master_leagues';

export class PaymentRefundError extends Error {}

const PLAN_PRODUCT_TYPES = new Set<string>(['plan_subscription']);
const VERIFICATION_PRODUCT_TYPES = new Set<string>(['organizer_verification', 'organizer_verification_renewal']);

export function isAutoRevokableProductType(productType: string): boolean {
  return (AUTO_REVOKABLE_PRODUCT_TYPES as readonly string[]).includes(productType);
}

export async function refundPayment(params: {
  paymentId: string;
  reason: string;
  revokeAccess: boolean;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<{ revokedEntitlement: boolean }> {
  const { paymentId, revokeAccess, actorUid, actorEmail } = params;
  const reason = params.reason.trim();

  if (!reason) {
    throw new PaymentRefundError('A refund reason is required.');
  }

  const ref = adminDb.collection(PAYMENTS_COLLECTION).doc(paymentId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new PaymentRefundError('Payment not found.');
  }

  const data = snap.data() ?? {};
  if (typeof data.refundedAtMs === 'number' && data.refundedAtMs > 0) {
    throw new PaymentRefundError('This payment has already been marked refunded.');
  }

  const nowMs = Date.now();
  const productType = (data.productType as string) ?? '';
  const masterLeagueId =
    (data.fulfilledMasterLeagueId as string) || (data.masterLeagueId as string) || '';

  await ref.update({
    refundedAtMs: nowMs,
    refundedByUid: actorUid,
    refundedByEmail: actorEmail ?? null,
    refundReason: reason,
  });

  let revokedEntitlement = false;

  if (revokeAccess && isAutoRevokableProductType(productType) && masterLeagueId) {
    const masterLeagueRef = adminDb.collection(MASTER_LEAGUES_COLLECTION).doc(masterLeagueId);
    const masterLeagueSnap = await masterLeagueRef.get();

    if (masterLeagueSnap.exists) {
      if (PLAN_PRODUCT_TYPES.has(productType)) {
        await masterLeagueRef.update({
          plan: 'basic',
          purchaseStatus: 'refunded',
          updatedAtMs: nowMs,
        });
        revokedEntitlement = true;
      } else if (VERIFICATION_PRODUCT_TYPES.has(productType)) {
        await masterLeagueRef.update({
          verifiedBadge: false,
          verificationStatus: 'none',
          verificationExpiresAtMs: 0,
          updatedAtMs: nowMs,
        });
        revokedEntitlement = true;
      }
    }
  }

  await recordAuditLog({
    actorUid,
    actorEmail,
    action: 'payment.refund',
    targetType: 'payment',
    targetId: paymentId,
    summary: `Marked payment ${paymentId} (${productType || 'unknown product'}, ${data.currency ?? ''} ${
      data.amountStr ?? data.amount ?? ''
    }) refunded for user ${data.userId ?? 'unknown'}. Reason: ${reason}.${
      revokedEntitlement ? ' Also revoked the access it granted.' : ' Access was not revoked.'
    }`,
  });

  return { revokedEntitlement };
}
