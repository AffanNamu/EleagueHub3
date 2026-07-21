import { payWithFlutterwave } from '@/lib/payments/flutterwavePay';
import { activatePlanAfterPayment } from './entitlements';
import { getOrganizerVerificationFee, getOrganizerVerificationRenewalFee, getPlanPrice, paymentsGloballyEnabled } from './pricing';
import { submitVerificationRequest } from './masterLeaguesRepository';
import { MasterLeaguePlanId, PlanDurationId } from '@/types/masterLeague';

// Thin wrappers over the generic payWithFlutterwave checkout — the same
// pattern as League access-fee payment, reused for plan subscriptions
// and organizer verification (initial + renewal). Nothing here
// re-implements payment logic; it only assembles the right
// productType/productSubType/metadata per flow.

export interface SimplePaymentResult {
  success: boolean;
  errorMessage?: string;
  receiptId?: string;
}

export async function payForPlanSubscription(
  plan: MasterLeaguePlanId,
  duration: PlanDurationId,
): Promise<SimplePaymentResult> {
  if (!(await paymentsGloballyEnabled())) {
    return { success: false, errorMessage: 'Payments are temporarily disabled by the administrator.' };
  }

  const price = await getPlanPrice(plan, duration);
  if (!price) {
    return {
      success: false,
      errorMessage: `${plan} ${duration} price isn't configured yet. Please try again later.`,
    };
  }

  const result = await payWithFlutterwave({
    amount: price.amount,
    currency: price.currency,
    productType: 'plan_subscription',
    productSubType: `plan_${plan}_${duration}`,
    planId: plan,
    planDurationId: duration,
    description: `${plan} plan (${duration}) subscription`,
    items: [
      {
        productType: 'plan_subscription',
        productSubType: `plan_${plan}_${duration}`,
        quantity: 1,
        amount: price.amount,
      },
    ],
    metadata: { plan, duration },
  });

  if (!result.success || !result.receiptId) {
    return { success: false, errorMessage: result.errorMessage || 'Payment failed.' };
  }

  // Set custom claims server-side + refresh token — required before the
  // master_leagues create write will pass firestore.rules.
  await activatePlanAfterPayment({
    plan,
    duration,
    provider: 'flutterwave',
    receiptId: result.receiptId,
  });

  return { success: true, receiptId: result.receiptId };
}

export async function payForOrganizerVerification(
  masterLeagueId: string,
  masterLeagueName: string,
  requestType: 'initial' | 'renewal',
  note?: string,
): Promise<SimplePaymentResult> {
  if (!(await paymentsGloballyEnabled())) {
    return { success: false, errorMessage: 'Payments are temporarily disabled by the administrator.' };
  }

  const fee =
    requestType === 'initial'
      ? await getOrganizerVerificationFee()
      : await getOrganizerVerificationRenewalFee();

  if (!fee) {
    return { success: false, errorMessage: 'Verification price is not configured correctly.' };
  }

  const productType =
    requestType === 'initial' ? 'organizer_verification' : 'organizer_verification_renewal';
  const productSubType =
    requestType === 'initial'
      ? 'master_league_organizer_verification'
      : 'master_league_organizer_verification_renewal';

  const result = await payWithFlutterwave({
    amount: fee.amount,
    currency: fee.currency,
    masterLeagueId,
    leagueName: masterLeagueName,
    productType,
    productSubType,
    description:
      requestType === 'initial'
        ? `Organizer verification: ${masterLeagueName}`
        : `Verification renewal: ${masterLeagueName}`,
    items: [{ productType, productSubType, quantity: 1, amount: fee.amount }],
    metadata: { masterLeagueId, verificationMode: requestType },
  });

  if (!result.success) {
    return { success: false, errorMessage: result.errorMessage || 'Payment failed.' };
  }

  await submitVerificationRequest({
    masterLeagueId,
    attemptId: result.attemptId,
    paymentId: result.paymentId,
    receiptId: result.receiptId || '',
    provider: 'flutterwave',
    note,
    requestType,
  });

  return { success: true, receiptId: result.receiptId };
}
