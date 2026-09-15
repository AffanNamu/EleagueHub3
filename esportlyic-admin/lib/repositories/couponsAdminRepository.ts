// lib/repositories/couponsAdminRepository.ts
//
// Read visibility into a league's coupon program plus the one safe
// management action available from here: toggling couponsEnabled on
// the league doc itself. Codes and redemptions
// (leagues/{id}/couponCodes/{code}, couponRedemptions/{uid}) are never
// created, edited, or deleted from here -- firestore.rules never allows
// a delete on either, and codes go from unused to used exactly once
// (coupon_codes_service.dart); this module preserves that invariant
// rather than using the Admin SDK to bypass it, since generating or
// voiding codes here without also updating couponConfig's
// qtyTotal/qtyRemaining bookkeeping the app relies on would desync the
// organizer's own view of their coupon program.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { CouponCode, CouponConfig, CouponRedemption } from '@/types/coupon';

const LEAGUES_COLLECTION = 'leagues';

export class CouponAdminError extends Error {}

function toCouponConfig(data: FirebaseFirestore.DocumentData): CouponConfig {
  return {
    leagueId: data.leagueId ?? '',
    organizerUserId: data.organizerUserId ?? '',
    currency: data.currency ?? 'NGN',
    unitPrice: typeof data.unitPrice === 'number' ? data.unitPrice : 0,
    effectiveUnit: typeof data.effectiveUnit === 'number' ? data.effectiveUnit : 0,
    threshold: typeof data.threshold === 'number' ? data.threshold : null,
    thresholdDiscountPercent: typeof data.thresholdDiscountPercent === 'number' ? data.thresholdDiscountPercent : 0,
    discountPercent: typeof data.discountPercent === 'number' ? data.discountPercent : 0,
    userPaysPercent: typeof data.userPaysPercent === 'number' ? data.userPaysPercent : 0,
    organizerPaysPercent: typeof data.organizerPaysPercent === 'number' ? data.organizerPaysPercent : 100,
    qtyTotal: typeof data.qtyTotal === 'number' ? data.qtyTotal : 0,
    qtyRemaining: typeof data.qtyRemaining === 'number' ? data.qtyRemaining : 0,
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

function toCouponCode(id: string, data: FirebaseFirestore.DocumentData): CouponCode {
  return {
    code: id,
    leagueId: data.leagueId ?? '',
    organizerUserId: data.organizerUserId ?? '',
    currency: data.currency ?? 'NGN',
    discountPercent: typeof data.discountPercent === 'number' ? data.discountPercent : 0,
    expectedAmount: typeof data.expectedAmount === 'number' ? data.expectedAmount : 0,
    usedBy: data.usedBy ?? '',
    usedAtMs: typeof data.usedAtMs === 'number' ? data.usedAtMs : 0,
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

function toCouponRedemption(id: string, data: FirebaseFirestore.DocumentData): CouponRedemption {
  return {
    userId: id,
    leagueId: data.leagueId ?? '',
    status: data.status ?? '',
    provider: data.provider ?? '',
    receiptId: data.receiptId ?? '',
    paidAtMs: typeof data.paidAtMs === 'number' ? data.paidAtMs : 0,
    currency: data.currency ?? 'NGN',
    expectedAmount: typeof data.expectedAmount === 'number' ? data.expectedAmount : 0,
    code: data.code ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

export async function getCouponConfig(leagueId: string): Promise<CouponConfig | null> {
  const snap = await adminDb
    .collection(LEAGUES_COLLECTION)
    .doc(leagueId)
    .collection('couponConfig')
    .doc('config')
    .get();
  if (!snap.exists) return null;
  return toCouponConfig(snap.data() ?? {});
}

export async function listCouponCodes(leagueId: string, limit = 200): Promise<CouponCode[]> {
  const snap = await adminDb
    .collection(LEAGUES_COLLECTION)
    .doc(leagueId)
    .collection('couponCodes')
    .orderBy('createdAtMs', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((doc) => toCouponCode(doc.id, doc.data()));
}

export async function listCouponRedemptions(leagueId: string, limit = 200): Promise<CouponRedemption[]> {
  const snap = await adminDb
    .collection(LEAGUES_COLLECTION)
    .doc(leagueId)
    .collection('couponRedemptions')
    .orderBy('createdAtMs', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((doc) => toCouponRedemption(doc.id, doc.data()));
}

export async function setLeagueCouponsEnabled(
  leagueId: string,
  enabled: boolean,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  const ref = adminDb.collection(LEAGUES_COLLECTION).doc(leagueId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new CouponAdminError('League not found.');
  }

  await ref.update({ couponsEnabled: enabled, updatedAtMs: Date.now() });

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: enabled ? 'league.coupons.enable' : 'league.coupons.disable',
    targetType: 'league',
    targetId: leagueId,
    summary: `${enabled ? 'Enabled' : 'Disabled'} coupons for league "${(snap.data()?.name as string) || leagueId}"`,
  });
}
