'use client';

import { Badge } from '@/components/ui/Badge';
import { formatRelativeTime } from '@/lib/utils';
import { useFootballHubPollerToggle } from '@/hooks/useFootballHubPollerToggle';

export function FootballHubPollerToggle({
  pollerEnabled,
  updatedAtMs,
  updatedByEmail,
}: {
  pollerEnabled: boolean;
  updatedAtMs: number | null;
  updatedByEmail: string | null;
}) {
  const { setPollerEnabled, pending, error } = useFootballHubPollerToggle();

  return (
    <div className="panel p-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-ink-primary">Live-score poller</p>
          <p className="mt-0.5 text-xs text-ink-secondary">
            Runs hourly, checks live matches, and sends goal/kickoff/full-time push notifications
            to followers. Turning this off stops the Worker's scheduled poll on its next run --
            no redeploy needed.
          </p>
          {updatedAtMs && (
            <p className="mt-1 text-xs text-ink-muted">
              Last changed {formatRelativeTime(updatedAtMs)}
              {updatedByEmail ? ` by ${updatedByEmail}` : ''}
            </p>
          )}
        </div>
        <button
          onClick={() => setPollerEnabled(!pollerEnabled)}
          disabled={pending}
          className="disabled:opacity-60"
        >
          <Badge tone={pollerEnabled ? 'success' : 'neutral'}>{pollerEnabled ? 'Enabled' : 'Paused'}</Badge>
        </button>
      </div>
      {error && <p className="mt-2 text-xs text-signal-danger">{error}</p>}
    </div>
  );
}
