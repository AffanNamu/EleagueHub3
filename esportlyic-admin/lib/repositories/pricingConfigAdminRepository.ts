// lib/repositories/pricingConfigAdminRepository.ts
//
// Server-only reader/writer for the app-wide pricing document that
// web_client (lib/masterLeagues/pricing.ts), the Flutter app
// (lib/core/services/remote_pricing_service.dart), and the Cloudflare
// Worker's payment verifier (worker/src/index.js, _readPricingConfig /
// _planSubscriptionExpectedFee) all read from.
//
// IMPORTANT: the primary doc is `app_config/pricing`, with `app/pricing`
// only as a fallback read when the primary doesn't exist — this exactly
// mirrors the read-side resolution in all three of those consumers.
// Writes always go to the primary doc, so admin edits are guaranteed to
// actually take effect (a previous version of this file only ever
// touched `app/pricing`, which — since `app_config/pricing` already
// exists in production — meant every edit made through this page had
// zero effect on real pricing or payment verification).
//
// Each currency (ngn/usd) is a nested map field on the doc; this file
// merges whatever partial data exists there on top of the same
// DEFAULTS_NGN/DEFAULTS_USD values web_client falls back to, so the
// admin UI always shows a complete, editable set of fields even if the
// live doc is missing some of them.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { CurrencyPricing, PricingConfig, PricingFieldEdit } from '@/types/pricingConfig';

const PRIMARY_DOC = { collection: 'app_config', doc: 'pricing' } as const;
const FALLBACK_DOC = { collection: 'app', doc: 'pricing' } as const;

// Keep in sync with DEFAULTS_USD / DEFAULTS_NGN in
// web_client/lib/masterLeagues/pricing.ts and the ngn/usd defaults in
// worker/src/index.js's _readPricingConfig.
const DEFAULTS_USD: CurrencyPricing = {
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

const DEFAULTS_NGN: CurrencyPricing = {
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

const NUMBER_KEYS = new Set<keyof CurrencyPricing>([
  'createLeagueFee', 'accessFee', 'couponUnit', 'couponThreshold', 'couponDiscountPercent',
  'premiumFee', 'premiumDurationDays',
  'proPlan1moFee', 'proPlan3moFee', 'proPlan6moFee', 'proPlanYearlyFee',
  'elitePlan1moFee', 'elitePlan3moFee', 'elitePlan6moFee', 'elitePlanYearlyFee',
  'masterLeagueBasicFee', 'masterLeagueProFee', 'masterLeagueEliteFee',
  'organizerVerificationFee', 'organizerVerificationRenewalFee', 'organizerVerificationDurationDays',
]);

const BOOLEAN_KEYS = new Set<keyof CurrencyPricing>([
  'premiumEnabled', 'organizerVerificationEnabled', 'organizerVerificationRenewalEnabled',
  'paymentsEnabled', 'flutterwaveEnabled',
]);

function mergeCurrency(raw: Record<string, unknown> | undefined, defaults: CurrencyPricing): CurrencyPricing {
  const map = raw && typeof raw === 'object' ? raw : {};
  const out = { ...defaults };
  for (const key of Object.keys(defaults) as (keyof CurrencyPricing)[]) {
    const v = map[key];
    if (key === 'couponThreshold') {
      if (v === null) out[key] = null;
      else if (typeof v === 'number' && Number.isFinite(v)) out[key] = v;
      continue;
    }
    if (NUMBER_KEYS.has(key) && typeof v === 'number' && Number.isFinite(v)) {
      (out[key] as number) = v;
    } else if (BOOLEAN_KEYS.has(key) && typeof v === 'boolean') {
      (out[key] as boolean) = v;
    }
  }
  return out;
}

export async function getPricingConfig(): Promise<PricingConfig> {
  let snap = await adminDb.collection(PRIMARY_DOC.collection).doc(PRIMARY_DOC.doc).get();
  let sourceDoc: PricingConfig['sourceDoc'] = 'app_config/pricing';

  if (!snap.exists) {
    snap = await adminDb.collection(FALLBACK_DOC.collection).doc(FALLBACK_DOC.doc).get();
    sourceDoc = snap.exists ? 'app/pricing' : 'defaults';
  }

  const data = snap.exists ? snap.data() ?? {} : {};

  return {
    ngn: mergeCurrency(data.ngn as Record<string, unknown> | undefined, DEFAULTS_NGN),
    usd: mergeCurrency(data.usd as Record<string, unknown> | undefined, DEFAULTS_USD),
    sourceDoc,
  };
}

export class PricingConfigError extends Error {}

function validateEdit(edit: PricingFieldEdit): void {
  const { key, value } = edit;

  if (key === 'couponThreshold') {
    if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
      throw new PricingConfigError(`"${key}" must be a non-negative number or null.`);
    }
    return;
  }

  if (BOOLEAN_KEYS.has(key)) {
    if (typeof value !== 'boolean') {
      throw new PricingConfigError(`"${key}" expects a boolean.`);
    }
    return;
  }

  if (NUMBER_KEYS.has(key)) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
      throw new PricingConfigError(`"${key}" must be a non-negative number.`);
    }
    return;
  }

  throw new PricingConfigError(`Unknown pricing field "${key}".`);
}

export async function updatePricingConfig(params: {
  edits: PricingFieldEdit[];
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  if (params.edits.length === 0) return;

  for (const edit of params.edits) validateEdit(edit);

  const ref = adminDb.collection(PRIMARY_DOC.collection).doc(PRIMARY_DOC.doc);

  // Dot-path keys (e.g. "ngn.proPlan1moFee") so this only touches the
  // exact fields being edited, leaving every sibling field on the ngn/usd
  // maps untouched. set({...}, {merge:true}) (rather than update()) so
  // this also works the very first time app_config/pricing is created.
  const updates: Record<string, number | boolean | null> = {};
  for (const edit of params.edits) {
    updates[`${edit.currency}.${edit.key}`] = edit.value;
  }

  await ref.set(updates, { merge: true });

  const summary = params.edits
    .map((e) => `${e.currency}.${e.key}=${e.value}`)
    .join(', ');

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'pricing.update',
    targetType: 'pricing_config',
    targetId: `${PRIMARY_DOC.collection}/${PRIMARY_DOC.doc}`,
    summary: `Updated pricing fields: ${summary}`,
  });
}
