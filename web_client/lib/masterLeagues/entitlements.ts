import { auth } from '@/lib/firebase';
import { MasterLeaguePlanId, PlanDurationId } from '@/types/masterLeague';

// Mirrors MasterLeagueEntitlementService.dart's claims path.
//
// IMPORTANT (flagged in chat): firestore.rules only allow a paid
// master_leagues create when the ID TOKEN carries
// organizerPro == true && organizerProPlan in ['pro','elite'].
// A Firestore profile write alone is NOT enough to pass the rule.
// So after a successful Flutterwave payment we must call the worker
// to set those claims server-side, then force-refresh the token.

export interface OrganizerEntitlement {
  active: boolean;
  plan: MasterLeaguePlanId | null;
  expiryMs: number;
  daysRemaining: number;
}

function activateUrl(): string | null {
  const base = (process.env.NEXT_PUBLIC_WORKER_BASE_URL || '').trim();
  if (!base) return null;
  return `${base.replace(/\/$/, '')}/organizer-pro/activate`;
}

export async function getEntitlementFromClaims(): Promise<OrganizerEntitlement> {
  const user = auth.currentUser;
  if (!user) return { active: false, plan: null, expiryMs: 0, daysRemaining: 0 };

  try {
    const result = await user.getIdTokenResult(false);
    const claims = result.claims || {};
    const active = claims.organizerPro === true;
    if (!active) return { active: false, plan: null, expiryMs: 0, daysRemaining: 0 };

    const plan = (claims.organizerProPlan as MasterLeaguePlanId) || null;
    if (plan !== 'pro' && plan !== 'elite') {
      return { active: false, plan: null, expiryMs: 0, daysRemaining: 0 };
    }

    const expiryMs = Number(claims.organizerProExpiryMs) || 0;
    const now = Date.now();
    if (expiryMs > 0 && expiryMs <= now) {
      return { active: false, plan: null, expiryMs: 0, daysRemaining: 0 };
    }

    const daysRemaining = expiryMs > now ? Math.ceil((expiryMs - now) / 86400000) : 0;
    return { active: true, plan, expiryMs, daysRemaining };
  } catch (e) {
    console.warn('[entitlements] getIdTokenResult failed:', e);
    return { active: false, plan: null, expiryMs: 0, daysRemaining: 0 };
  }
}

/**
 * Calls the worker to verify + record the purchase and set custom claims,
 * then force-refreshes the ID token so subsequent Firestore writes see the
 * new claims immediately.
 *
 * NOTE: this hits the SAME worker path Flutter's
 * MasterLeagueEntitlementService.activateAfterPayment uses. If your worker
 * route differs, only this function needs to change.
 */
export async function activatePlanAfterPayment(params: {
  plan: MasterLeaguePlanId;
  duration: PlanDurationId;
  provider: 'flutterwave';
  receiptId: string;
}): Promise<void> {
  const user = auth.currentUser;
  if (!user) throw new Error('Please sign in and try again.');

  const uri = activateUrl();
  if (!uri) {
    throw new Error(
      'Plan activation service is not configured. Missing NEXT_PUBLIC_WORKER_BASE_URL.',
    );
  }

  const idToken = await user.getIdToken(true);
  const res = await fetch(uri, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      plan: params.plan,
      duration: params.duration,
      provider: params.provider,
      receiptId: params.receiptId,
    }),
  });

  const parsed = await res.json().catch(() => ({}));
  if (!res.ok || parsed.success !== true) {
    throw new Error(parsed.error || `Plan activation failed (${res.status}).`);
  }

  // Force a fresh token so request.auth.token.organizerPro is visible
  // to firestore.rules on the very next write.
  await user.getIdToken(true);
}
