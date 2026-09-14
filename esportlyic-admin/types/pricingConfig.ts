// types/pricingConfig.ts
//
// Confirmed schema — mirrors RemotePricingPlan in
// web_client/lib/masterLeagues/pricing.ts and _readPricingConfig's field
// list in worker/src/index.js exactly. Both of those are the real
// consumers (display price + authoritative payment-verification amount),
// so this type must keep matching them field-for-field.

export interface CurrencyPricing {
  createLeagueFee: number;
  accessFee: number;
  couponUnit: number;
  couponThreshold: number | null;
  couponDiscountPercent: number;
  premiumFee: number;
  premiumDurationDays: number;
  premiumEnabled: boolean;
  proPlan1moFee: number;
  proPlan3moFee: number;
  proPlan6moFee: number;
  proPlanYearlyFee: number;
  elitePlan1moFee: number;
  elitePlan3moFee: number;
  elitePlan6moFee: number;
  elitePlanYearlyFee: number;
  masterLeagueBasicFee: number;
  masterLeagueProFee: number;
  masterLeagueEliteFee: number;
  organizerVerificationFee: number;
  organizerVerificationEnabled: boolean;
  organizerVerificationRenewalFee: number;
  organizerVerificationRenewalEnabled: boolean;
  organizerVerificationDurationDays: number;
  paymentsEnabled: boolean;
  flutterwaveEnabled: boolean;
}

export type CurrencyCode = 'ngn' | 'usd';

export interface PricingConfig {
  ngn: CurrencyPricing;
  usd: CurrencyPricing;
  /** Which Firestore doc this was actually read from, for the "editing X" banner. */
  sourceDoc: 'app_config/pricing' | 'app/pricing' | 'defaults';
}

/** A single edited cell, addressed by currency + field key. */
export interface PricingFieldEdit {
  currency: CurrencyCode;
  key: keyof CurrencyPricing;
  value: number | boolean | null;
}
