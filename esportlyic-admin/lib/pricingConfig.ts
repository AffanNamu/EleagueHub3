// lib/pricingConfig.ts
//
// Server-only reader for app/pricing — the same document
// pricing_admin_screen.dart edits from the mobile app.
//
// NOTE — FIELD NAME NOT YET CONFIRMED: the pricing screen's controller
// names for organizer verification fee/renewal fee/duration were not
// captured in full detail during the architecture review (only the
// screen's general structure was). getVerificationDurationDays() below
// tries a short list of plausible field names and falls back to a
// documented default. Please confirm the real field name against the
// live app/pricing document (or pricing_admin_screen.dart's controller
// for "verification duration days") and this can be narrowed to a single
// exact key.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';

const CANDIDATE_DURATION_FIELDS = [
  'organizerVerificationDurationDays',
  'verificationDurationDays',
  'verificationValidityDays',
] as const;

const DEFAULT_VERIFICATION_DURATION_DAYS = 365;

export async function getVerificationDurationDays(): Promise<number> {
  const snap = await adminDb.collection('app').doc('pricing').get();
  if (!snap.exists) return DEFAULT_VERIFICATION_DURATION_DAYS;

  const data = snap.data() ?? {};
  for (const field of CANDIDATE_DURATION_FIELDS) {
    const value = data[field];
    if (typeof value === 'number' && value > 0) return value;
  }

  return DEFAULT_VERIFICATION_DURATION_DAYS;
}
