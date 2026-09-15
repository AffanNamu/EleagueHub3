'use client';

import { Ticket } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { useLeagueCouponsToggle } from '@/hooks/useLeagueCoupons';
import { formatRelativeTime } from '@/lib/utils';
import type { CouponCode, CouponConfig, CouponRedemption } from '@/types/coupon';

const CURRENCY_SYMBOL: Record<string, string> = { NGN: '₦', USD: '$' };

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="panel p-4">
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-1 font-display text-lg font-semibold text-ink-primary">{value}</p>
    </div>
  );
}

export function LeagueCouponsPanel({
  leagueId,
  couponsEnabled,
  config,
  codes,
  redemptions,
  canManage,
}: {
  leagueId: string;
  couponsEnabled: boolean;
  config: CouponConfig | null;
  codes: CouponCode[];
  redemptions: CouponRedemption[];
  canManage: boolean;
}) {
  const { setEnabled, submitting, error } = useLeagueCouponsToggle(leagueId);
  const usedCount = codes.filter((c) => c.usedBy).length;
  const unusedCount = codes.length - usedCount;
  const currencySymbol = config ? CURRENCY_SYMBOL[config.currency] ?? '' : '';

  return (
    <div className="space-y-4">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="panel flex items-center justify-between gap-4 p-5">
        <div>
          <h2 className="font-display text-sm font-semibold text-ink-primary">Coupon Program</h2>
          <p className="mt-1 text-sm text-ink-secondary">
            {couponsEnabled ? 'Coupons are enabled for this league.' : 'Coupons are disabled for this league.'}
          </p>
        </div>
        {canManage && (
          <button
            onClick={() => setEnabled(!couponsEnabled)}
            disabled={submitting}
            className="rounded-sm border border-base-border px-3 py-1.5 text-sm font-medium text-ink-primary hover:bg-base-raised disabled:opacity-60"
          >
            {submitting ? 'Saving…' : couponsEnabled ? 'Disable coupons' : 'Enable coupons'}
          </button>
        )}
      </div>

      {config ? (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat label="Codes Generated" value={config.qtyTotal} />
          <Stat label="Codes Remaining" value={config.qtyRemaining} />
          <Stat label="Discount" value={`${config.discountPercent}%`} />
          <Stat
            label="Unit Price"
            value={`${currencySymbol}${config.unitPrice}`}
          />
        </div>
      ) : (
        <EmptyState icon={Ticket} title="No coupon program configured for this league" />
      )}

      {codes.length > 0 && (
        <div className="panel overflow-hidden">
          <div className="flex items-center justify-between border-b border-base-border px-4 py-3">
            <h3 className="font-display text-sm font-semibold text-ink-primary">Coupon Codes</h3>
            <p className="text-xs text-ink-muted">
              {unusedCount} unused · {usedCount} used{codes.length >= 200 ? ' (showing latest 200)' : ''}
            </p>
          </div>
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-base-border text-left text-xs text-ink-muted">
                <th className="px-4 py-2 font-medium">Code</th>
                <th className="px-4 py-2 font-medium">Discount</th>
                <th className="px-4 py-2 font-medium">Status</th>
                <th className="px-4 py-2 font-medium">Used By</th>
                <th className="px-4 py-2 font-medium">Created</th>
              </tr>
            </thead>
            <tbody>
              {codes.map((code) => (
                <tr key={code.code} className="border-b border-base-border last:border-0">
                  <td className="px-4 py-2 font-mono text-xs text-ink-primary">{code.code}</td>
                  <td className="px-4 py-2 text-ink-secondary">{code.discountPercent}%</td>
                  <td className="px-4 py-2">
                    {code.usedBy ? <Badge tone="neutral">Used</Badge> : <Badge tone="success">Available</Badge>}
                  </td>
                  <td className="px-4 py-2 text-ink-secondary">{code.usedBy || '—'}</td>
                  <td className="px-4 py-2 text-ink-secondary">
                    {code.createdAtMs ? formatRelativeTime(code.createdAtMs) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {redemptions.length > 0 && (
        <div className="panel overflow-hidden">
          <div className="border-b border-base-border px-4 py-3">
            <h3 className="font-display text-sm font-semibold text-ink-primary">Redemptions</h3>
          </div>
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-base-border text-left text-xs text-ink-muted">
                <th className="px-4 py-2 font-medium">User</th>
                <th className="px-4 py-2 font-medium">Code</th>
                <th className="px-4 py-2 font-medium">Amount</th>
                <th className="px-4 py-2 font-medium">Paid</th>
              </tr>
            </thead>
            <tbody>
              {redemptions.map((redemption) => (
                <tr key={redemption.userId} className="border-b border-base-border last:border-0">
                  <td className="px-4 py-2 text-ink-primary">{redemption.userId}</td>
                  <td className="px-4 py-2 font-mono text-xs text-ink-secondary">{redemption.code}</td>
                  <td className="px-4 py-2 text-ink-secondary">
                    {CURRENCY_SYMBOL[redemption.currency] ?? ''}
                    {redemption.expectedAmount}
                  </td>
                  <td className="px-4 py-2 text-ink-secondary">
                    {redemption.paidAtMs ? formatRelativeTime(redemption.paidAtMs) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
