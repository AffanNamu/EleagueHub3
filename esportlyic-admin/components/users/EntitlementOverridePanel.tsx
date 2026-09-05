'use client';

import { useState } from 'react';
import { AlertTriangle } from 'lucide-react';
import { useEntitlementOverrideAction } from '@/hooks/useEntitlementOverrideAction';
import { formatRelativeTime } from '@/lib/utils';
import type { AdminUserProfile } from '@/types/user';

const DURATIONS = [
  { id: '3mo', label: '3 Months', days: 90 },
  { id: '6mo', label: '6 Months', days: 180 },
  { id: 'yearly', label: '1 Year', days: 365 },
];

export function EntitlementOverridePanel({ profile }: { profile: AdminUserProfile }) {
  const { grant, revoke, submitting, error } = useEntitlementOverrideAction(profile.userId);
  const [plan, setPlan] = useState<'pro' | 'elite'>('pro');
  const [durationId, setDurationId] = useState('3mo');

  const { claims } = profile;
  const claimsActive = claims.organizerPro && (claims.organizerProExpiryMs ?? 0) > Date.now();

  function handleGrant() {
    const duration = DURATIONS.find((d) => d.id === durationId)!;
    const expiresAtMs = Date.now() + duration.days * 24 * 60 * 60 * 1000;
    if (!confirm(`Grant ${plan} (${duration.label}) to this user, bypassing payment verification?`)) return;
    grant(plan, durationId, expiresAtMs);
  }

  return (
    <div className="panel space-y-3 border-signal-warning/30 p-5">
      <div className="flex items-start gap-2">
        <AlertTriangle size={16} className="mt-0.5 flex-shrink-0 text-signal-warning" />
        <div>
          <h2 className="font-display text-sm font-semibold text-ink-primary">Entitlement Override</h2>
          <p className="mt-0.5 text-xs text-ink-secondary">
            Bypasses payment verification entirely. Custom claims only take effect on the user's
            next token refresh — not instant.
          </p>
        </div>
      </div>

      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="rounded-sm bg-base-raised px-3 py-2.5">
        <p className="text-xs text-ink-muted">Current claims state</p>
        {claimsActive ? (
          <p className="mt-1 text-sm text-ink-primary">
            {claims.organizerProPlan} ({claims.organizerProDuration}) — expires{' '}
            {formatRelativeTime(claims.organizerProExpiryMs!)}
          </p>
        ) : (
          <p className="mt-1 text-sm text-ink-secondary">No active organizerPro claim.</p>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="mb-1 block text-xs text-ink-secondary">Plan</label>
          <select
            value={plan}
            onChange={(event) => setPlan(event.target.value as 'pro' | 'elite')}
            className="w-full rounded-sm border border-base-border bg-base-raised px-2 py-1.5 text-sm text-ink-primary outline-none focus:border-brand"
          >
            <option value="pro">Pro</option>
            <option value="elite">Elite</option>
          </select>
        </div>
        <div>
          <label className="mb-1 block text-xs text-ink-secondary">Duration</label>
          <select
            value={durationId}
            onChange={(event) => setDurationId(event.target.value)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-2 py-1.5 text-sm text-ink-primary outline-none focus:border-brand"
          >
            {DURATIONS.map((d) => (
              <option key={d.id} value={d.id}>
                {d.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      <button
        onClick={handleGrant}
        disabled={submitting}
        className="w-full rounded-sm bg-signal-warning py-2 text-sm font-medium text-base disabled:opacity-60"
      >
        {submitting ? 'Applying…' : 'Grant Entitlement'}
      </button>

      {claimsActive && (
        <button
          onClick={() => revoke()}
          disabled={submitting}
          className="w-full rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-signal-danger hover:text-signal-danger disabled:opacity-60"
        >
          Revoke Current Entitlement
        </button>
      )}
    </div>
  );
}
