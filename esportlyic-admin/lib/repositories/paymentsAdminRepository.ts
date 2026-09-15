// lib/repositories/paymentsAdminRepository.ts

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import type { Payment, PaymentAttempt, RevenueByCurrency } from '@/types/payment';

function toPayment(id: string, data: FirebaseFirestore.DocumentData): Payment {
  return {
    paymentId: id,
    attemptId: data.attemptId ?? '',
    provider: (data.provider as Payment['provider']) ?? 'flutterwave',
    providerTransactionId: data.providerTransactionId ?? '',
    txRef: data.txRef ?? '',
    receiptId: data.receiptId ?? '',
    userId: data.userId ?? '',
    leagueId: data.leagueId ?? '',
    leagueName: data.leagueName ?? '',
    masterLeagueId: data.masterLeagueId ?? '',
    masterLeagueName: data.masterLeagueName ?? '',
    couponCode: data.couponCode ?? '',
    currency: (data.currency as Payment['currency']) ?? 'NGN',
    amount: typeof data.amount === 'number' ? data.amount : 0,
    amountStr: data.amountStr ?? '',
    productType: data.productType ?? '',
    productSubType: data.productSubType ?? '',
    productId: data.productId ?? '',
    paidAtMs: typeof data.paidAtMs === 'number' ? data.paidAtMs : 0,
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
    fulfilledMasterLeagueId: data.fulfilledMasterLeagueId ?? '',
    fulfilledVerificationRequestId: data.fulfilledVerificationRequestId ?? '',
    fulfilledAtMs: typeof data.fulfilledAtMs === 'number' ? data.fulfilledAtMs : 0,
    purchaseToken: data.purchaseToken ?? '',
    refundedAtMs: typeof data.refundedAtMs === 'number' ? data.refundedAtMs : 0,
    refundedByUid: data.refundedByUid ?? '',
    refundedByEmail: data.refundedByEmail ?? null,
    refundReason: data.refundReason ?? '',
  };
}

export async function listPayments(params: { limit?: number } = {}): Promise<Payment[]> {
  const { limit = 100 } = params;
  const snap = await adminDb.collection('payments').orderBy('createdAtMs', 'desc').limit(limit).get();
  return snap.docs.map((doc) => toPayment(doc.id, doc.data()));
}

export async function getPayment(paymentId: string): Promise<Payment | null> {
  const snap = await adminDb.collection('payments').doc(paymentId).get();
  if (!snap.exists) return null;
  return toPayment(snap.id, snap.data() ?? {});
}

export async function getPaymentsForUser(userId: string, limit = 20): Promise<Payment[]> {
  const snap = await adminDb
    .collection('payments')
    .where('userId', '==', userId)
    .orderBy('createdAtMs', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((doc) => toPayment(doc.id, doc.data()));
}

export async function getPaymentAttempt(attemptId: string): Promise<PaymentAttempt | null> {
  if (!attemptId) return null;
  const snap = await adminDb.collection('payment_attempts').doc(attemptId).get();
  if (!snap.exists) return null;

  const data = snap.data() ?? {};
  return {
    attemptId: snap.id,
    userId: data.userId ?? '',
    provider: (data.provider as PaymentAttempt['provider']) ?? 'flutterwave',
    currency: (data.currency as PaymentAttempt['currency']) ?? 'NGN',
    amount: typeof data.amount === 'number' ? data.amount : 0,
    amountStr: data.amountStr ?? '',
    status: (data.status as PaymentAttempt['status']) ?? 'initiated',
    productType: data.productType ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

export async function getRevenueSummary(): Promise<RevenueByCurrency[]> {
  const snap = await adminDb.collection('payments').orderBy('createdAtMs', 'desc').limit(500).get();

  const totals = new Map<string, { total: number; count: number }>();
  for (const doc of snap.docs) {
    const data = doc.data();
    const currency = (data.currency as string) ?? 'NGN';
    const amount = typeof data.amount === 'number' ? data.amount : 0;
    const existing = totals.get(currency) ?? { total: 0, count: 0 };
    totals.set(currency, { total: existing.total + amount, count: existing.count + 1 });
  }

  return Array.from(totals.entries()).map(([currency, { total, count }]) => ({
    currency: currency as RevenueByCurrency['currency'],
    total,
    count,
  }));
}

export interface ProviderUserCounts {
  flutterwave: number;
  googlePlay: number;
  manual: number;
  noProvider: number;
}

/**
 * Counts USERS by their current plan's provider (users.planProvider),
 * not payment transaction counts — this answers "how many registered
 * users currently hold a plan through each provider", which is what's
 * useful for a company dashboard. Google Play appears under two
 * historical field values ('google_play_billing' and 'google_play') per
 * the rules-confirmed provider list, so both are summed as one figure.
 */
export async function getUserCountsByProvider(): Promise<ProviderUserCounts> {
  const usersRef = adminDb.collection('users');

  const [flutterwave, googlePlayBilling, googlePlayLegacy, manual, totalWithPlan] = await Promise.all([
    usersRef.where('planProvider', '==', 'flutterwave').count().get(),
    usersRef.where('planProvider', '==', 'google_play_billing').count().get(),
    usersRef.where('planProvider', '==', 'google_play').count().get(),
    usersRef.where('planProvider', '==', 'manual').count().get(),
    usersRef.where('activePlanId', 'in', ['pro', 'elite']).count().get(),
  ]);

  const flutterwaveCount = flutterwave.data().count;
  const googlePlayCount = googlePlayBilling.data().count + googlePlayLegacy.data().count;
  const manualCount = manual.data().count;
  const noProvider = Math.max(0, totalWithPlan.data().count - flutterwaveCount - googlePlayCount - manualCount);

  return {
    flutterwave: flutterwaveCount,
    googlePlay: googlePlayCount,
    manual: manualCount,
    noProvider,
  };
}
