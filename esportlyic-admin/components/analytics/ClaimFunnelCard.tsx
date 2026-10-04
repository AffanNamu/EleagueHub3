import type { ClaimFunnelBreakdown } from '@/lib/repositories/analyticsAdminRepository';

export function ClaimFunnelCard({ data }: { data: ClaimFunnelBreakdown }) {
  const base = data.stages[0]?.count ?? 0;

  return (
    <div className="panel p-5">
      <h2 className="font-display text-sm font-semibold text-ink-primary">Team Claim Funnel</h2>
      <p className="mt-1 mb-4 text-xs text-ink-muted">
        Manually-created (external) teams, from creation through an organizer-generated claim link to a
        real account claiming it. &quot;Claim flow started&quot; isn&apos;t tagged to a specific team, so
        its share of the base is directional, not an exact conversion rate.
      </p>
      <div className="space-y-2.5">
        {data.stages.map((stage, i) => {
          const pct = base > 0 ? (stage.count / base) * 100 : 0;
          return (
            <div key={stage.label}>
              <div className="mb-1 flex items-center justify-between text-sm">
                <span className="text-ink-secondary">{stage.label}</span>
                <span className="text-ink-primary">
                  {stage.count}
                  {i > 0 && base > 0 && (
                    <span className="ml-1.5 text-xs text-ink-muted">({pct.toFixed(0)}%)</span>
                  )}
                </span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-base-raised">
                <div className="h-full rounded-full bg-brand" style={{ width: `${Math.min(100, pct)}%` }} />
              </div>
            </div>
          );
        })}
      </div>

      <div className="mt-4 flex items-center gap-5 border-t border-base-border pt-3 text-xs text-ink-secondary">
        <span>
          Failed claim attempts: <span className="text-ink-primary">{data.failedCount}</span>
        </span>
        <span>
          Revoked links: <span className="text-ink-primary">{data.revokedCount}</span>
        </span>
      </div>
    </div>
  );
}
