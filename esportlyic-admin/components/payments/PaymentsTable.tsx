import Link from 'next/link';
import { CreditCard } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { formatRelativeTime } from '@/lib/utils';
import type { Payment } from '@/types/payment';

const CURRENCY_SYMBOL: Record<string, string> = { NGN: '₦', USD: '$', PLAY: '' };

export function PaymentsTable({ payments }: { payments: Payment[] }) {
  if (payments.length === 0) {
    return <EmptyState icon={CreditCard} title="No payments recorded yet" />;
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">Payment</th>
            <th className="px-4 py-3 font-medium">Product</th>
            <th className="px-4 py-3 font-medium">Provider</th>
            <th className="px-4 py-3 font-medium">Amount</th>
            <th className="px-4 py-3 font-medium">Date</th>
          </tr>
        </thead>
        <tbody>
          {payments.map((payment) => (
            <tr key={payment.paymentId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
              <td className="px-4 py-3">
                <Link href={`/payments/${payment.paymentId}`}>
                  <p className="font-medium text-ink-primary">{payment.userId}</p>
                  <p className="text-xs text-ink-muted">{payment.paymentId}</p>
                </Link>
              </td>
              <td className="px-4 py-3 text-ink-secondary">
                {payment.productType || '—'}
                {payment.productSubType ? ` / ${payment.productSubType}` : ''}
              </td>
              <td className="px-4 py-3">
                <Badge tone="brand" className="capitalize">
                  {payment.provider.replace(/_/g, ' ')}
                </Badge>
              </td>
              <td className="px-4 py-3 text-ink-secondary">
                {CURRENCY_SYMBOL[payment.currency] ?? ''}
                {payment.amountStr || payment.amount}
              </td>
              <td className="px-4 py-3 text-ink-secondary">
                {payment.createdAtMs ? formatRelativeTime(payment.createdAtMs) : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
