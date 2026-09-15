// types/coupon.ts
//
// Types sourced from firestore.rules' leagues/{leagueId}/couponConfig/config,
// couponCodes/{codeId}, and couponRedemptions/{uid} field allow-lists
// (firestore.rules:2047-2098), cross-checked against
// coupon_config_service.dart / coupon_codes_service.dart. Coupon codes
// are one-time-use once redeemed and the rules never allow a delete on
// any of these three docs -- that's a deliberate audit-trail invariant
// this admin panel respects (see couponsAdminRepository.ts).

export interface CouponConfig {
  leagueId: string;
  organizerUserId: string;
  currency: string;
  unitPrice: number;
  effectiveUnit: number;
  threshold: number | null;
  thresholdDiscountPercent: number;
  discountPercent: number;
  userPaysPercent: number;
  organizerPaysPercent: number;
  qtyTotal: number;
  qtyRemaining: number;
  createdAtMs: number;
  updatedAtMs: number;
}

export interface CouponCode {
  code: string;
  leagueId: string;
  organizerUserId: string;
  currency: string;
  discountPercent: number;
  expectedAmount: number;
  usedBy: string;
  usedAtMs: number;
  createdAtMs: number;
  updatedAtMs: number;
}

export interface CouponRedemption {
  userId: string;
  leagueId: string;
  status: string;
  provider: string;
  receiptId: string;
  paidAtMs: number;
  currency: string;
  expectedAmount: number;
  code: string;
  createdAtMs: number;
  updatedAtMs: number;
}
