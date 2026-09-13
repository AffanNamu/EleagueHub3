// web_client/lib/masterLeagues/pricing.ts
//
// Web port of lib/core/services/remote_pricing_service.dart. Reads the
// SAME Firestore doc the worker validates payment amounts against
// (app_config/pricing, falling back to app/pricing), with the SAME
// top-level ngn/usd sub-maps and per-field fallback chains as both the
// Dart RemotePricingPlan.fromMap and worker/src/index.js's
// _readPricingConfig/mergeCurrency — see that function for the
// authoritative field list this must keep matching.
//
// Previously this file (and lib/payments/pricingService.ts and
// lib/payments/remotePricing.ts, both now deleted) each guessed a
// DIFFERENT, wrong shape for this doc, so getPlanPrice/getRemotePricingPlan
// always returned 0 or a hardcoded default in production — silently
// breaking every real Flutterwave charge amount on web.

import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { resolveCountryCodeWeb } from '@/lib/countryResolver';
import { MasterLeaguePlanId, PlanDurationId } from '@/types/masterLeague';

export interface PlanPrice {
  amount: number;
  currency: string;
}

export interface RemotePricingPlan {
  currency: string;
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

const DEFAULTS_USD: RemotePricingPlan = {
  currency: 'USD',
  createLeagueFee: 5.0,
  accessFee: 1.5,
  couponUnit: 1.5,
  couponThreshold: 20.0,
  couponDiscountPercent: 30,
  premiumFee: 9.99,
  premiumDurationDays: 30,
  premiumEnabled: true,
  proPlan1moFee: 4.0,
  proPlan3moFee: 10.0,
  proPlan6moFee: 18.0,
  proPlanYearlyFee: 30.0,
  elitePlan1moFee: 8.0,
  elitePlan3moFee: 20.0,
  elitePlan6moFee: 36.0,
  elitePlanYearlyFee: 60.0,
  masterLeagueBasicFee: 5.0,
  masterLeagueProFee: 10.0,
  masterLeagueEliteFee: 20.0,
  organizerVerificationFee: 15.0,
  organizerVerificationEnabled: true,
  organizerVerificationRenewalFee: 12.0,
  organizerVerificationRenewalEnabled: true,
  organizerVerificationDurationDays: 90,
  paymentsEnabled: true,
  flutterwaveEnabled: true,
};

const DEFAULTS_NGN: RemotePricingPlan = {
  currency: 'NGN',
  createLeagueFee: 4000.0,
  accessFee: 1000.0,
  couponUnit: 1000.0,
  couponThreshold: null,
  couponDiscountPercent: 30,
  premiumFee: 5000.0,
  premiumDurationDays: 30,
  premiumEnabled: true,
  proPlan1moFee: 2000.0,
  proPlan3moFee: 5000.0,
  proPlan6moFee: 9000.0,
  proPlanYearlyFee: 15000.0,
  elitePlan1moFee: 4000.0,
  elitePlan3moFee: 10000.0,
  elitePlan6moFee: 18000.0,
  elitePlanYearlyFee: 30000.0,
  masterLeagueBasicFee: 1500.0,
  masterLeagueProFee: 3000.0,
  masterLeagueEliteFee: 5000.0,
  organizerVerificationFee: 10000.0,
  organizerVerificationEnabled: true,
  organizerVerificationRenewalFee: 8000.0,
  organizerVerificationRenewalEnabled: true,
  organizerVerificationDurationDays: 90,
  paymentsEnabled: true,
  flutterwaveEnabled: true,
};

function num(v: unknown, fallback: number): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = parseFloat(v);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

function bool(v: unknown, fallback: boolean): boolean {
  return typeof v === 'boolean' ? v : fallback;
}

function fromMap(currency: string, map: Record<string, unknown>, defaults: RemotePricingPlan): RemotePricingPlan {
  const createFee = map.createFee ?? map.createLeagueFee;
  const mlBasic = map.masterLeagueBasicFee ?? map.masterLinkBasicFee ?? map.masterLinkFee ?? map.masterLeagueFee;
  const mlPro = map.masterLeagueProFee ?? map.masterLinkProFee ?? map.masterLinkFee ?? map.masterLeagueFee;
  const mlElite = map.masterLeagueEliteFee ?? map.masterLinkEliteFee ?? map.masterLinkFee ?? map.masterLeagueFee;
  const verificationFee = map.organizerVerificationFee ?? map.verificationFee;
  const verificationEnabled = map.organizerVerificationEnabled ?? map.verificationEnabled;
  const renewalFee = map.organizerVerificationRenewalFee ?? map.verificationRenewalFee;
  const renewalEnabled = map.organizerVerificationRenewalEnabled ?? map.verificationRenewalEnabled;
  const renewalDays = map.organizerVerificationDurationDays ?? map.verificationDurationDays;

  return {
    currency,
    createLeagueFee: num(createFee, defaults.createLeagueFee),
    accessFee: num(map.accessFee, defaults.accessFee),
    couponUnit: num(map.couponUnit, defaults.couponUnit),
    couponThreshold:
      map.couponThreshold === undefined
        ? defaults.couponThreshold
        : (num(map.couponThreshold, 0) || null),
    couponDiscountPercent: num(map.couponDiscountPercent, defaults.couponDiscountPercent),
    premiumFee: num(map.premiumFee, defaults.premiumFee),
    premiumDurationDays: num(map.premiumDurationDays, defaults.premiumDurationDays),
    premiumEnabled: bool(map.premiumEnabled, defaults.premiumEnabled),
    proPlan1moFee: num(map.proPlan1moFee, defaults.proPlan1moFee),
    proPlan3moFee: num(map.proPlan3moFee, defaults.proPlan3moFee),
    proPlan6moFee: num(map.proPlan6moFee, defaults.proPlan6moFee),
    proPlanYearlyFee: num(map.proPlanYearlyFee, defaults.proPlanYearlyFee),
    elitePlan1moFee: num(map.elitePlan1moFee, defaults.elitePlan1moFee),
    elitePlan3moFee: num(map.elitePlan3moFee, defaults.elitePlan3moFee),
    elitePlan6moFee: num(map.elitePlan6moFee, defaults.elitePlan6moFee),
    elitePlanYearlyFee: num(map.elitePlanYearlyFee, defaults.elitePlanYearlyFee),
    masterLeagueBasicFee: num(mlBasic, defaults.masterLeagueBasicFee),
    masterLeagueProFee: num(mlPro, defaults.masterLeagueProFee),
    masterLeagueEliteFee: num(mlElite, defaults.masterLeagueEliteFee),
    organizerVerificationFee: num(verificationFee, defaults.organizerVerificationFee),
    organizerVerificationEnabled: bool(verificationEnabled, defaults.organizerVerificationEnabled),
    organizerVerificationRenewalFee: num(renewalFee, defaults.organizerVerificationRenewalFee),
    organizerVerificationRenewalEnabled: bool(renewalEnabled, defaults.organizerVerificationRenewalEnabled),
    organizerVerificationDurationDays: num(renewalDays, defaults.organizerVerificationDurationDays),
    paymentsEnabled: bool(map.paymentsEnabled, defaults.paymentsEnabled),
    flutterwaveEnabled: bool(map.flutterwaveEnabled, defaults.flutterwaveEnabled),
  };
}

interface PricingCache {
  fetchedAtMs: number;
  ngn: RemotePricingPlan;
  usd: RemotePricingPlan;
}

let cache: PricingCache | null = null;
const CACHE_TTL_MS = 10 * 60 * 1000;

async function fetchPricing(): Promise<PricingCache> {
  try {
    let snap = await getDoc(doc(db, 'app_config', 'pricing'));
    if (!snap.exists()) snap = await getDoc(doc(db, 'app', 'pricing'));

    if (!snap.exists()) {
      return { fetchedAtMs: Date.now(), ngn: DEFAULTS_NGN, usd: DEFAULTS_USD };
    }

    const raw = snap.data() || {};
    const ngnMap = (raw.ngn && typeof raw.ngn === 'object') ? raw.ngn : {};
    const usdMap = (raw.usd && typeof raw.usd === 'object') ? raw.usd : {};

    return {
      fetchedAtMs: Date.now(),
      ngn: fromMap('NGN', ngnMap, DEFAULTS_NGN),
      usd: fromMap('USD', usdMap, DEFAULTS_USD),
    };
  } catch (e) {
    console.warn('[pricing] failed to load app_config/pricing:', e);
    return { fetchedAtMs: Date.now(), ngn: DEFAULTS_NGN, usd: DEFAULTS_USD };
  }
}

async function getCache(): Promise<PricingCache> {
  if (!cache || Date.now() - cache.fetchedAtMs > CACHE_TTL_MS) {
    cache = await fetchPricing();
  }
  return cache;
}

/** Full pricing plan for the visitor's resolved country (NG -> NGN, else USD). */
export async function getRemotePricingPlan(): Promise<RemotePricingPlan> {
  const [c, countryCode] = await Promise.all([getCache(), resolveCountryCodeWeb()]);
  return countryCode.trim().toUpperCase() === 'NG' ? c.ngn : c.usd;
}

export async function paymentsGloballyEnabled(): Promise<boolean> {
  const plan = await getRemotePricingPlan();
  return plan.paymentsEnabled;
}

export async function getPlanPrice(
  plan: MasterLeaguePlanId,
  duration: PlanDurationId,
): Promise<PlanPrice | null> {
  const cfg = await getRemotePricingPlan();

  // Mirrors _planSubscriptionExpectedFee in worker/src/index.js exactly —
  // keep both in sync if a new plan/duration is ever added.
  const feesByPlan: Partial<Record<MasterLeaguePlanId, Record<PlanDurationId, number>>> = {
    pro: {
      '3mo': cfg.proPlan3moFee,
      '6mo': cfg.proPlan6moFee,
      yearly: cfg.proPlanYearlyFee,
    },
    elite: {
      '3mo': cfg.elitePlan3moFee,
      '6mo': cfg.elitePlan6moFee,
      yearly: cfg.elitePlanYearlyFee,
    },
  };

  const amount = feesByPlan[plan]?.[duration];
  if (!amount || !Number.isFinite(amount) || amount <= 0) return null;
  return { amount, currency: cfg.currency };
}

export async function getOrganizerVerificationFee(): Promise<PlanPrice | null> {
  const cfg = await getRemotePricingPlan();
  if (!cfg.organizerVerificationEnabled || cfg.organizerVerificationFee <= 0) return null;
  return { amount: cfg.organizerVerificationFee, currency: cfg.currency };
}

export async function getOrganizerVerificationRenewalFee(): Promise<PlanPrice | null> {
  const cfg = await getRemotePricingPlan();
  if (!cfg.organizerVerificationRenewalEnabled || cfg.organizerVerificationRenewalFee <= 0) return null;
  return { amount: cfg.organizerVerificationRenewalFee, currency: cfg.currency };
}
