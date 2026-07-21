import { doc, collection, getDoc, setDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { workerFlutterwaveVerifyUrl } from './flutterwaveConfig';
import { PaymentAttemptCreate, PaymentVerificationResult } from './paymentModels';

function nowMs(): number {
  return Date.now();
}

export async function createAttempt(attempt: PaymentAttemptCreate): Promise<string> {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid || attempt.userId.trim() !== uid) return '';

  try {
    const ref = doc(collection(db, 'payment_attempts'));
    const createdAtMs = nowMs();

    await setDoc(ref, {
      attemptId: ref.id,
      provider: attempt.provider,
      currency: attempt.currency,
      amount: attempt.amount,
      amountStr: attempt.amountStr,
      userId: attempt.userId,
      leagueId: attempt.leagueId ?? '',
      leagueName: attempt.leagueName ?? '',
      masterLeagueId: attempt.masterLeagueId ?? '',
      couponCode: attempt.couponCode ?? '',
      productType: attempt.productType ?? '',
      productSubType: attempt.productSubType ?? '',
      planId: attempt.planId ?? '',
      planDurationId: attempt.planDurationId ?? '',
      metadata: attempt.metadata ?? {},
      status: 'initiated',
      createdAtMs,
      updatedAtMs: createdAtMs,
      items: attempt.items,
    });

    return ref.id;
  } catch (e) {
    console.error('[paymentsService] createAttempt failed:', e);
    return '';
  }
}

async function updateAttemptStatus(
  attemptId: string,
  fields: Record<string, unknown>,
): Promise<void> {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid || !attemptId.trim()) return;

  try {
    const ref = doc(db, 'payment_attempts', attemptId.trim());
    const snap = await getDoc(ref);
    if (!snap.exists()) return;
    const existing = snap.data();
    if ((existing.userId ?? '').toString().trim() !== uid) return;

    await setDoc(
      ref,
      { ...existing, ...fields, updatedAtMs: nowMs() },
      { merge: false },
    );
  } catch (e) {
    console.error('[paymentsService] updateAttemptStatus failed:', e);
  }
}

export async function markClientCancelled(attemptId: string, reason: string): Promise<void> {
  await updateAttemptStatus(attemptId, { status: 'cancelled', errorMessage: reason });
}

export async function markClientFailed(attemptId: string, errorMessage: string): Promise<void> {
  await updateAttemptStatus(attemptId, { status: 'client_failed', errorMessage });
}

function cleanErrorMessage(error: unknown): string {
  const raw = String(error instanceof Error ? error.message : error).trim();
  if (raw.includes('Payment verification endpoint was not found')) {
    return 'Payment verification service is not available right now. Please contact support or try again later.';
  }
  if (raw.includes('Failed to fetch')) {
    return 'Network error while verifying payment. Please check your internet and try again.';
  }
  return raw;
}

export async function verifyFlutterwavePayment(params: {
  attemptId: string;
  transactionId: string;
  txRef: string;
}): Promise<PaymentVerificationResult> {
  const user = auth.currentUser;
  const uid = user?.uid.trim() ?? '';

  if (!uid) {
    return failedVerification('Please sign in again and retry.', params);
  }
  if (!params.attemptId.trim()) {
    return failedVerification('Missing payment attempt.', params);
  }
  if (!params.transactionId.trim()) {
    return failedVerification('Missing transaction id.', params);
  }

  try {
    const verifyUri = workerFlutterwaveVerifyUrl();
    if (!verifyUri) {
      throw new Error(
        'Payment verification service is not configured. Missing NEXT_PUBLIC_WORKER_BASE_URL.',
      );
    }

    const idToken = await user!.getIdToken(true);
    if (!idToken?.trim()) {
      return failedVerification('Unable to get authentication token. Please sign in again.', params);
    }

    const res = await fetch(verifyUri, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${idToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        attemptId: params.attemptId.trim(),
        transactionId: params.transactionId.trim(),
        txRef: params.txRef.trim(),
        userId: uid,
      }),
    });

    const parsed = await res.json().catch(() => ({}));

    if (!res.ok) {
      if (res.status === 404) {
        throw new Error('Payment verification endpoint was not found (404).');
      }
      throw new Error(parsed.error || `Payment verification failed (${res.status}).`);
    }

    const success = parsed.success === true;
    if (!success) {
      await markClientFailed(
        params.attemptId,
        parsed.error?.trim() || 'Payment verification failed.',
      );
    }

    return {
      success,
      provider: (parsed.provider || 'flutterwave').trim(),
      paymentId: (parsed.paymentId || '').trim(),
      receiptId: (parsed.receiptId || '').trim(),
      paidAtMs: Number(parsed.paidAtMs) || 0,
      transactionId: (parsed.transactionId || params.transactionId).trim(),
      txRef: (parsed.txRef || params.txRef).trim(),
      status: (parsed.status || '').trim(),
      currency: (parsed.currency || '').trim(),
      amount: Number(parsed.amount) || 0,
      amountStr: (parsed.amountStr || '').trim(),
      errorMessage: parsed.error?.trim(),
      raw: parsed,
    };
  } catch (e) {
    await markClientFailed(params.attemptId, `Verification failed: ${e}`);
    return failedVerification(cleanErrorMessage(e), params);
  }
}

function failedVerification(
  errorMessage: string,
  params: { attemptId: string; transactionId: string; txRef: string },
): PaymentVerificationResult {
  return {
    success: false,
    provider: 'flutterwave',
    paymentId: '',
    receiptId: '',
    paidAtMs: 0,
    transactionId: params.transactionId,
    txRef: params.txRef,
    status: 'failed',
    currency: '',
    amount: 0,
    amountStr: '0',
    errorMessage,
    raw: {},
  };
}
