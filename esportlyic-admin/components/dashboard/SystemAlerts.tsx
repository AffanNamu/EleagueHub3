import { CheckCircle2, AlertTriangle, AlertOctagon } from 'lucide-react';
import type { SystemHealthAlert } from '@/lib/repositories/dashboardRepository';

// Alerts are computed live from real backlog ages on every dashboard
// load (see getSystemHealthAlerts in dashboardRepository.ts) -- there's
// still no automated alerting pipeline (no Cloud Function, no
// system_alerts collection watching error rates/quotas), so this only
// ever reflects what's true right now, not a historical alert feed.

export function SystemAlerts({ alerts }: { alerts: SystemHealthAlert[] }) {
  if (alerts.length === 0) {
    return (
      <div className="panel p-5">
        <h2 className="mb-4 font-display text-sm font-semibold text-ink-primary">System Alerts</h2>
        <div className="flex items-start gap-3 rounded-sm bg-base-raised px-3 py-3">
          <CheckCircle2 size={16} className="mt-0.5 flex-shrink-0 text-signal-success" />
          <div>
            <p className="text-sm text-ink-primary">No aging backlogs detected</p>
            <p className="mt-0.5 text-xs text-ink-secondary">
              Reports, verification requests, and Global Chat requests are all within their normal
              review window.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="panel p-5">
      <h2 className="mb-4 font-display text-sm font-semibold text-ink-primary">System Alerts</h2>
      <div className="space-y-2">
        {alerts.map((alert) => (
          <div
            key={alert.id}
            className={`flex items-start gap-3 rounded-sm px-3 py-3 ${
              alert.severity === 'danger' ? 'bg-signal-dangerFaint' : 'bg-signal-warningFaint'
            }`}
          >
            {alert.severity === 'danger' ? (
              <AlertOctagon size={16} className="mt-0.5 flex-shrink-0 text-signal-danger" />
            ) : (
              <AlertTriangle size={16} className="mt-0.5 flex-shrink-0 text-signal-warning" />
            )}
            <div>
              <p className="text-sm text-ink-primary">{alert.title}</p>
              <p className="mt-0.5 text-xs text-ink-secondary">{alert.detail}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
