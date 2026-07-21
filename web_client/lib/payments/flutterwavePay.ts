import { v4 as uuidv4 } from 'uuid';
import { auth } from '@/lib/firebase';
import { FlutterwaveConfig } from './flutterwaveConfig';
import { openFlutterwaveCheckout } from './flutterwaveClient';
import * as PaymentsService from './paymentsService';
import { PaymentLineItem, PaymentVerificationResult } from './paymentModels';

export interface FlutterwavePayResult {
  success: boolean;
  errorMessage?: string;
  receiptId?: string;
  paidAtMs: number;
  totalAmount: string;
  attemptId: string;
  paymentId: string;
  transactionId: string;
  txRef: string;
  paymentMethod?: string;
}

export interface FlutterwavePayParams {
  amount: number;
  currency: string;
  leagueId?: string;
  leagueName?: string;
  masterLeagueId?: string;
  couponCode?: string;
  productType: string;
  productSubType: string;
  planId?: string;
  planDurationId?: string;
  description: string;
  items: PaymentLineItem[];
  metadata?: Record<string, unknown>;
}

function toFlutterwaveAmount(v: number): string {
  const rounded = Math.round(v * 100) / 100;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2);
}

export async function payWithFlutterwave(params: FlutterwavePayParams): Promise<FlutterwavePayResult> {
  const user = auth.currentUser;
  if (!user) {
    return failed('Please sign in to continue.');
  }

  let attemptId = '';

  try {
    FlutterwaveConfig.assertConfigured();

    if (params.amount <= 0) {
      const now = Date.now();
      return {
        success: true,
        receiptId: `FREE-${now}`,
        paidAtMs: now,
        totalAmount: '0',
        attemptId: '',
        paymentId: '',
        transactionId: '',
        txRef: '',
      };
    }

    const totalAmount = toFlutterwaveAmount(params.amount);

    attemptId = await PaymentsService.createAttempt({
      provider: 'flutterwave',
      currency: params.currency,
      amount: params.amount,
      amountStr: totalAmount,
      userId: user.uid,
      leagueId: params.leagueId ?? '',
      leagueName: params.leagueName ?? '',
      masterLeagueId: params.masterLeagueId ?? '',
      couponCode: params.couponCode ?? '',
      productType: params.productType,
      productSubType: params.productSubType,
      planId: params.planId ?? '',
      planDurationId: params.planDurationId ?? '',
      metadata: params.metadata ?? {},
      items: params.items,
    });

    if (!attemptId) {
      return failed('Unable to start payment. Please try again.');
    }

    const txRef = `EH-WEB-${Date.now()}-${uuidv4()}`;

    const charge = await openFlutterwaveCheckout({
      publicKey: FlutterwaveConfig.publicKey,
      txRef,
      amount: totalAmount,
      currency: params.currency,
      redirectUrl: FlutterwaveConfig.redirectUrl,
      customerEmail: user.email || `user_${user.uid}@esportlyic.app`,
      customerPhone: user.phoneNumber || '0000000000',
      customerName: user.displayName || 'eSportlyic User',
      title: 'eSportlyic',
      description: params.description,
      isTestMode: FlutterwaveConfig.isTestMode,
    });

    if (charge.cancelled || !charge.success) {
      await PaymentsService.markClientCancelled(attemptId, 'Payment cancelled or not successful');
      return failed('Payment cancelled or not successful', attemptId, totalAmount);
    }

    if (!charge.transactionId) {
      await PaymentsService.markClientFailed(attemptId, 'Missing transactionId.');
      return failed('Missing transaction id.', attemptId, totalAmount);
    }

    const verification: PaymentVerificationResult = await PaymentsService.verifyFlutterwavePayment({
      attemptId,
      transactionId: charge.transactionId,
      txRef: charge.txRef || txRef,
    });

    if (!verification.success) {
      return failed(
        verification.errorMessage || 'Payment verification failed.',
        attemptId,
        totalAmount,
        verification.paymentId,
        charge.transactionId,
        charge.txRef,
      );
    }

    return {
      success: true,
      receiptId: verification.receiptId,
      paidAtMs: verification.paidAtMs,
      totalAmount: verification.amountStr || totalAmount,
      attemptId,
      paymentId: verification.paymentId,
      transactionId: verification.transactionId,
      txRef: verification.txRef,
      paymentMethod: charge.paymentMethod,
    };
  } catch (e) {
    if (attemptId) {
      await PaymentsService.markClientFailed(attemptId, String(e));
    }
    return failed(e instanceof Error ? e.message : String(e), attemptId);
  }
}

function failed(
  errorMessage: string,
  attemptId = '',
  totalAmount = '0',
  paymentId = '',
  transactionId = '',
  txRef = '',
): FlutterwavePayResult {
  return {
    success: false,
    errorMessage,
    paidAtMs: 0,
    totalAmount,
    attemptId,
    paymentId,
    transactionId,
    txRef,
  };
}
