// types/payment.ts
//
// Types sourced directly from firestore.rules' payments/{paymentId} and
// payment_attempts/{attemptId} field allow-lists — authoritative
// regardless of exact Dart enum naming, since these ARE the shapes the
// database enforces. Key fact baked into this module: a payments/{id}
// document's `status` is ALWAYS 'success' at creation and the update
// rule never includes `status` in its allowed changedKeys — so every
// row in this collection is a successful, immutable-status payment.
// Revenue math never needs to filter by status.

export type PaymentProvider = 'flutterwave' | 'free' | 'google_play_billing' | 'google_play';
export type PaymentCurrency = 'NGN' | 'USD' | 'PLAY';
export type PaymentAttemptStatus = 'initiated' | 'client_success' | 'cancelled' | 'client_failed' | 'verified' | 'fulfilled';

export interface Payment {
  paymentId: string;
  attemptId: string;
  provider: PaymentProvider;
  providerTransactionId: string;
  txRef: string;
  receiptId: string;
  userId: string;
  leagueId: string;
  leagueName: string;
  masterLeagueId: string;
  masterLeagueName: string;
  couponCode: string;
  currency: PaymentCurrency;
  amount: number;
  amountStr: string;
  productType: string;
  productSubType: string;
  productId: string;
  paidAtMs: number;
  createdAtMs: number;
  updatedAtMs: number;
  fulfilledMasterLeagueId: string;
  fulfilledVerificationRequestId: string;
  fulfilledAtMs: number;
  purchaseToken: string;
}

export interface PaymentAttempt {
  attemptId: string;
  userId: string;
  provider: PaymentProvider;
  currency: PaymentCurrency;
  amount: number;
  amountStr: string;
  status: PaymentAttemptStatus;
  productType: string;
  createdAtMs: number;
  updatedAtMs: number;
}

export interface RevenueByCurrency {
  currency: PaymentCurrency;
  total: number;
  count: number;
}
