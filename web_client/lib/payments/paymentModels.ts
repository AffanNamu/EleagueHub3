export type PaymentProvider = 'flutterwave' | 'free';

export interface PaymentLineItem {
  productType: string;
  productSubType: string;
  quantity: number;
  amount: number;
}

export interface PaymentAttemptCreate {
  provider: PaymentProvider;
  currency: string;
  amount: number;
  amountStr: string;
  userId: string;
  leagueId?: string;
  leagueName?: string;
  masterLeagueId?: string;
  couponCode?: string;
  productType?: string;
  productSubType?: string;
  planId?: string;
  planDurationId?: string;
  metadata?: Record<string, unknown>;
  items: PaymentLineItem[];
}

export interface PaymentVerificationResult {
  success: boolean;
  provider: string;
  paymentId: string;
  receiptId: string;
  paidAtMs: number;
  transactionId: string;
  txRef: string;
  status: string;
  currency: string;
  amount: number;
  amountStr: string;
  errorMessage?: string;
  raw: Record<string, unknown>;
}
