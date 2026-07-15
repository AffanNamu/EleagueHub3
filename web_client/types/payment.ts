export interface PaymentLineItem {
  productType: string;
  productSubType: string;
  quantity: number;
  amount: number;
}

export interface PaymentAttemptCreate {
  provider: string;
  currency: string;
  amount: number;
  amountStr: string;
  userId: string;
  leagueId: string;
  leagueName: string;
  items: PaymentLineItem[];
  masterLeagueId?: string;
  couponCode?: string;
  productType?: string;
  productSubType?: string;
  planId?: string;
  planDurationId?: string;
  metadata?: Record<string, any>;
}

export interface ClientRecordPaymentResult {
  paymentId: string;
  receiptId: string;
  paidAtMs: number;
}
