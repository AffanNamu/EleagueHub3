import { AlertTriangle, Globe2 } from 'lucide-react';
import { formatNumber } from '@/lib/utils';
import type { CountryBreakdown } from '@/lib/repositories/analyticsAdminRepository';

export function CountryBreakdownCard({ data }: { data: CountryBreakdown }) {
  const { rows, recordedCount, totalUserCount, sampleCapped } = data;
  const coveragePct = totalUserCount > 0 ? Math.round((recordedCount / totalUserCount) * 100) : 0;
  const top = rows.slice(0, 8);
  const maxCount = top[0]?.count ?? 1;

  return (
    <div className="panel p-5">
      <div className="mb-3 flex items-center gap-2">
        <Globe2 size={16} className="text-ink-secondary" />
        <h2 className="font-display text-sm font-semibold text-ink-primary">Users by Country</h2>
      </div>

      <div className="mb-4 space-y-2">
        <div className="flex items-start gap-2 rounded-sm border border-signal-warning/30 bg-signal-warningFaint px-3 py-2">
          <AlertTriangle size={14} className="mt-0.5 flex-shrink-0 text-signal-warning" />
          <p className="text-xs text-ink-secondary">
            <span className="font-medium text-ink-primary">Nigeria is likely overcounted.</span>{' '}
            Country is detected for currency selection, not analytics — whenever detection fails
            for any reason, it silently defaults to Nigeria. Treat the NG figure as an upper bound,
            not a precise count.
          </p>
        </div>
        <p className="text-xs text-ink-muted">
          Recorded for {formatNumber(recordedCount)} of {formatNumber(totalUserCount)} users ({coveragePct}% coverage)
          {sampleCapped ? ' — sampled from the 2,000 most recently active records' : ''}.
        </p>
      </div>

      {rows.length === 0 ? (
        <p className="text-sm text-ink-secondary">No country data recorded yet.</p>
      ) : (
        <div className="space-y-2.5">
          {top.map((row) => (
            <div key={row.label}>
              <div className="mb-1 flex items-center justify-between text-sm">
                <span className="text-ink-secondary">{row.label}</span>
                <span className="text-ink-primary">{row.count}</span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-base-raised">
                <div
                  className="h-full rounded-full bg-brand"
                  style={{ width: `${(row.count / maxCount) * 100}%` }}
                />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
