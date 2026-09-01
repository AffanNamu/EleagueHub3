import { doc, setDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { v4 as uuidv4 } from 'uuid';

export interface PaymentAttemptPayload {
  provider: string;
  currency: string;
  amount: number;
  amountStr: string;
  userId: string;
  leagueId: string;
  leagueName: string;
  masterLeagueId: string;
  masterLeagueName: string;
  couponCode: string;
  productType: string;
  productSubType: string;
  planId: string;
  planDurationId: string;
  metadata: Record<string, any>;
  items: any[];
}

// ── 1. Create Attempt (STRICT PARITY WITH FIRESTORE RULES) ──
export async function createPaymentAttemptWeb(payload: PaymentAttemptPayload): Promise<string> {
  const attemptId = `flw_web_${Date.now()}_${uuidv4().substring(0, 8)}`;
  const ref = doc(db, 'payment_attempts', attemptId);
  const now = Date.now();

  // MUST match exactly the `hasOnly` fields in firestore.rules
  await setDoc(ref, {
    attemptId,
    provider: payload.provider,
    currency: payload.currency,
    amount: payload.amount,
    amountStr: payload.amountStr,
    userId: payload.userId,
    leagueId: payload.leagueId || '',
    leagueName: payload.leagueName || '',
    masterLeagueId: payload.masterLeagueId || '',
    masterLeagueName: payload.masterLeagueName || '',
    couponCode: payload.couponCode || '',
    productType: payload.productType || '',
    productSubType: payload.productSubType || '',
    planId: payload.planId || '',
    planDurationId: payload.planDurationId || '',
    metadata: payload.metadata || {},
    status: 'initiated',
    createdAtMs: now,
    updatedAtMs: now,
    items: payload.items || [],
  });

  return attemptId;
}

// ── 2. Mark Attempt Failed/Cancelled ──
export async function markAttemptFailedWeb(attemptId: string, errorMessage: string, status: string = 'client_failed') {
  if (!attemptId) return;
  const ref = doc(db, 'payment_attempts', attemptId);
  await setDoc(ref, { status, errorMessage, updatedAtMs: Date.now() }, { merge: true });
}

// ── 3. Verify & Activate with Backend Worker ──
// Mirrors _postJson to _activateUri() in master_league_entitlement_service.dart
export async function activatePlanViaWorkerWeb({
  planId, durationId, receiptId, provider = 'flutterwave'
}: {
  planId: string; durationId: string; receiptId: string; provider?: string;
}): Promise<void> {
  const user = auth.currentUser;
  if (!user) throw new Error("Authentication required.");

  const idToken = await user.getIdToken(true);
  
  // Replace with your actual Cloudflare Worker URL (EH_WORKER_BASE_URL)
  const workerBaseUrl = process.env.NEXT_PUBLIC_WORKER_BASE_URL || 'https://esportlyic.workers.dev';
  const activateUrl = `${workerBaseUrl}/organizer-pro/activate`;

  const response = await fetch(activateUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      plan: planId,
      duration: durationId,
      provider,
      receiptId,
    }),
  });

  const data = await response.json();
  
  if (!response.ok || !data.success) {
    throw new Error(data.error || 'Organizer Pro activation failed.');
  }

  // Force refresh the token locally to pick up the new custom claims immediately
  await user.getIdToken(true);
}
