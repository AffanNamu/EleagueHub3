import { CheckCircle2 } from 'lucide-react';

// No automated alerting system exists yet — there is no collection or
// Cloud Function producing system health alerts anywhere in the current
// codebase. Rather than show fabricated alert rows, this component is
// honest about that until a real alerting pipeline is built (likely a
// Cloud Function writing to a new `system_alerts` collection, watching
// error rates / payment failures / Firestore quota, etc).

export function SystemAlerts() {
  return (
    <div className="panel p-5">
      <h2 className="mb-4 font-display text-sm font-semibold text-ink-primary">System Alerts</h2>
      <div className="flex items-start gap-3 rounded-sm bg-base-raised px-3 py-3">
        <CheckCircle2 size={16} className="mt-0.5 flex-shrink-0 text-signal-success" />
        <div>
          <p className="text-sm text-ink-primary">No automated alerting configured</p>
          <p className="mt-0.5 text-xs text-ink-secondary">
            This panel will surface real alerts once a system-health pipeline is built.
          </p>
        </div>
      </div>
    </div>
  );
}
