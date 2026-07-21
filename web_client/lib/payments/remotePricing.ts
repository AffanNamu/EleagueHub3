import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface RemotePricingPlan {
  currency: string;
  createLeagueFee: number;
  accessFee: number;
  paymentsEnabled: boolean;
  flutterwaveEnabled: boolean;
}

// BUG FIXED: Defaults are now set to TRUE so payments are unblocked automatically
const DEFAULT_PLAN: RemotePricingPlan = {
  currency: 'USD',
  createLeagueFee: 0,
  accessFee: 0,
  paymentsEnabled: true, 
  flutterwaveEnabled: true, 
};

function num(v: unknown, fallback = 0): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = parseFloat(v);
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}

function bool(v: unknown, fallback = false): boolean {
  return typeof v === 'boolean' ? v : fallback;
}

export async function getRemotePricingPlan(): Promise<RemotePricingPlan> {
  try {
    const snap = await getDoc(doc(db, 'app', 'pricing'));
    if (!snap.exists()) return DEFAULT_PLAN;
    const d = snap.data();

    // If the database document exists but a specific field is missing, it falls back to our new TRUE defaults
    return {
      currency: (typeof d.currency === 'string' && d.currency.trim()) || DEFAULT_PLAN.currency,
      createLeagueFee: num(d.createLeagueFee, DEFAULT_PLAN.createLeagueFee),
      accessFee: num(d.accessFee, DEFAULT_PLAN.accessFee),
      // Check if it's explicitly set to false in DB, otherwise assume true based on fallback
      paymentsEnabled: d.paymentsEnabled !== undefined ? bool(d.paymentsEnabled) : DEFAULT_PLAN.paymentsEnabled,
      flutterwaveEnabled: d.flutterwaveEnabled !== undefined ? bool(d.flutterwaveEnabled) : DEFAULT_PLAN.flutterwaveEnabled,
    };
  } catch (e) {
    console.warn('[remotePricing] failed to load app/pricing:', e);
    return DEFAULT_PLAN; // Returns TRUE now
  }
}
