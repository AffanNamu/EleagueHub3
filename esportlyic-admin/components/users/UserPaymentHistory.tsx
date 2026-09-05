import Link from 'next/link';
import { formatRelativeTime } from '@/lib/utils';
import type { Payment } from '@/types/payment';

const CURRENCY_SYMBOL: Record<string, string> = { NGN: '₦', USD: '$', PLAY: '' };

export function UserPaymentHistory({ payments }: { payments: Payment[] }) {
  return (
    <div className="panel p-5">
      <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Payment History</h2>
      {payments.length === 0 ? (
        <p className="text-sm text-ink-secondary">No payments on record for this user.</p>
      ) : (
        <div className="space-y-2">
          {payments.map((payment) => (
            <Link
              key={payment.paymentId}
              href={`/payments/${payment.paymentId}`}
              className="flex items-center justify-between rounded-sm bg-base-raised px-3 py-2 text-sm hover:bg-base-border/40"
            >
              <div>
                <p className="text-ink-primary">
                  {payment.productType || 'Unknown'}
                  {payment.productSubType ? ` / ${payment.productSubType}` : ''}
                </p>
                <p className="text-xs text-ink-muted capitalize">{payment.provider.replace(/_/g, ' ')}</p>
              </div>
              <div className="text-right">
                <p className="text-ink-primary">
                  {CURRENCY_SYMBOL[payment.currency] ?? ''}
                  {payment.amountStr || payment.amount}
                </p>
                <p className="text-xs text-ink-muted">
                  {payment.createdAtMs ? formatRelativeTime(payment.createdAtMs) : '—'}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
