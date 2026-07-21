import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MasterLeaguePlanId, PlanDurationId } from '@/types/masterLeague';

// Reads app/pricing (same publicly-readable doc Flutter reads).
//
// ASSUMPTION FLAGGED: I don't know the exact nested shape your pricing
// doc uses for per-plan/per-duration amounts, so I'm reading a
// `planPricing` map keyed "pro_3mo" / "elite_yearly" etc, and a flat
// `organizerVerificationFee` / `organizerVerificationRenewalFee` field.
// If your actual doc looks different, send me the shape and I'll fix
// this one file only — nothing downstream needs to change.

export interface PlanPrice {
  amount: number;
  currency: string;
}

async function pricingDoc(): Promise<Record<string, any>> {
  const snap = await getDoc(doc(db, 'app', 'pricing'));
  return snap.exists() ? snap.data() : {};
}

export async function getPlanPrice(
  plan: MasterLeaguePlanId,
  duration: PlanDurationId,
): Promise<PlanPrice | null> {
  const data = await pricingDoc();
  const currency = (data.currency || 'USD').toString().trim().toUpperCase();
  const map = (data.planPricing || {}) as Record<string, number>;
  const key = `${plan}_${duration}`;
  const amount = Number(map[key]);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  return { amount, currency };
}

export async function getOrganizerVerificationFee(): Promise<PlanPrice | null> {
  const data = await pricingDoc();
  const currency = (data.currency || 'USD').toString().trim().toUpperCase();
  const amount = Number(data.organizerVerificationFee);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  return { amount, currency };
}

export async function getOrganizerVerificationRenewalFee(): Promise<PlanPrice | null> {
  const data = await pricingDoc();
  const currency = (data.currency || 'USD').toString().trim().toUpperCase();
  const amount = Number(data.organizerVerificationRenewalFee);
  if (!Number.isFinite(amount) || amount <= 0) return null;
  return { amount, currency };
}

export async function paymentsGloballyEnabled(): Promise<boolean> {
  const data = await pricingDoc();
  return data.paymentsEnabled === true;
}
