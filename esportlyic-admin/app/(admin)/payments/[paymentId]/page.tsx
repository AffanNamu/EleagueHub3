import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { getPayment, getPaymentAttempt } from '@/lib/repositories/paymentsAdminRepository';
import { formatRelativeTime } from '@/lib/utils';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-0.5 break-all text-sm text-ink-primary">{value || '—'}</p>
    </div>
  );
}

export default async function PaymentDetailPage({ params }: { params: { paymentId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'payments.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view payments.</p>
      </div>
    );
  }

  const payment = await getPayment(params.paymentId);
  if (!payment) notFound();

  const attempt = await getPaymentAttempt(payment.attemptId);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Payments', href: '/payments' }, { label: payment.paymentId }]} />

      <div className="panel p-5">
        <h1 className="font-display text-lg font-semibold text-ink-primary">Payment Details</h1>
        <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Field label="User ID" value={payment.userId} />
          <Field label="Provider" value={payment.provider} />
          <Field label="Amount" value={`${payment.currency} ${payment.amountStr || payment.amount}`} />
          <Field label="Product Type" value={payment.productType} />
          <Field label="Product Sub-Type" value={payment.productSubType} />
          <Field label="Product ID" value={payment.productId} />
          <Field label="League" value={payment.leagueName || payment.leagueId} />
          <Field label="Organizer Workspace" value={payment.masterLeagueName || payment.masterLeagueId} />
          <Field label="Coupon Code" value={payment.couponCode} />
          <Field label="Provider Transaction ID" value={payment.providerTransactionId} />
          <Field label="Transaction Ref" value={payment.txRef} />
          <Field label="Receipt ID" value={payment.receiptId} />
          <Field label="Purchase Token" value={payment.purchaseToken} />
          <Field label="Paid" value={payment.paidAtMs ? formatRelativeTime(payment.paidAtMs) : '—'} />
          <Field label="Created" value={payment.createdAtMs ? formatRelativeTime(payment.createdAtMs) : '—'} />
        </div>
      </div>

      {(payment.fulfilledMasterLeagueId || payment.fulfilledVerificationRequestId) && (
        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Fulfillment</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <Field label="Fulfilled Master League" value={payment.fulfilledMasterLeagueId} />
            <Field label="Fulfilled Verification Request" value={payment.fulfilledVerificationRequestId} />
            <Field label="Fulfilled At" value={payment.fulfilledAtMs ? formatRelativeTime(payment.fulfilledAtMs) : '—'} />
          </div>
        </div>
      )}

      {attempt && (
        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Originating Attempt</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <Field label="Attempt ID" value={attempt.attemptId} />
            <Field label="Attempt Status" value={attempt.status} />
            <Field label="Attempted" value={attempt.createdAtMs ? formatRelativeTime(attempt.createdAtMs) : '—'} />
          </div>
        </div>
      )}
    </div>
  );
}
