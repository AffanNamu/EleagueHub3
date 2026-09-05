import { formatNumber } from '@/lib/utils';
import type { RevenueByCurrency } from '@/types/payment';

const CURRENCY_SYMBOL: Record<string, string> = {
  NGN: '₦',
  USD: '$',
  PLAY: '',
};

export function RevenueSummaryCard({ summary }: { summary: RevenueByCurrency[] }) {
  if (summary.length === 0) {
    return (
      <div className="panel p-5">
        <p className="text-sm text-ink-secondary">No payments recorded yet.</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
      {summary.map((row) => (
        <div key={row.currency} className="panel p-4">
          <p className="text-xs text-ink-muted">{row.currency} Revenue (last 500 payments)</p>
          <p className="mt-1 font-display text-xl font-semibold text-ink-primary">
            {CURRENCY_SYMBOL[row.currency] ?? ''}
            {formatNumber(row.total)}
          </p>
          <p className="mt-0.5 text-xs text-ink-secondary">{row.count} transactions</p>
        </div>
      ))}
    </div>
  );
}
