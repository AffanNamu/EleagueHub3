'use client';

import { useState } from 'react';
import { formatRelativeTime } from '@/lib/utils';
import { useFootballHubApiKey } from '@/hooks/useFootballHubApiKey';

export function FootballHubApiKeyForm({
  configured,
  maskedKey,
  keyUpdatedAtMs,
  keyUpdatedByEmail,
}: {
  configured: boolean;
  maskedKey: string | null;
  keyUpdatedAtMs: number | null;
  keyUpdatedByEmail: string | null;
}) {
  const [value, setValue] = useState('');
  const [saved, setSaved] = useState(false);
  const { setApiKey, pending, error } = useFootballHubApiKey();

  async function handleSave() {
    setSaved(false);
    const key = value.trim();
    if (!key) return;
    const ok = await setApiKey(key);
    if (ok) {
      setValue('');
      setSaved(true);
    }
  }

  return (
    <div className="panel p-4 space-y-3">
      <div>
        <p className="text-sm font-medium text-ink-primary">API-Football key</p>
        <p className="mt-0.5 text-xs text-ink-secondary">
          Get a key from dashboard.api-football.com (not RapidAPI -- different auth scheme). Saving
          here takes effect within 5 minutes with no Worker redeploy. Leave the GitHub Actions
          secret as a fallback for new deployments; whichever is set here always wins.
        </p>
        {configured ? (
          <p className="mt-1 text-xs text-ink-muted">
            Current key: <span className="font-mono">{maskedKey}</span>
            {keyUpdatedAtMs && (
              <>
                {' '}
                &middot; last changed {formatRelativeTime(keyUpdatedAtMs)}
                {keyUpdatedByEmail ? ` by ${keyUpdatedByEmail}` : ''}
              </>
            )}
          </p>
        ) : (
          <p className="mt-1 text-xs text-ink-muted">
            Not set here yet -- the Worker is using its API_FOOTBALL_KEY secret.
          </p>
        )}
      </div>

      <div className="flex items-center gap-2">
        <input
          type="password"
          placeholder="Paste the API-Football key"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          className="w-full max-w-md rounded-sm border border-base-border bg-base-raised px-2.5 py-1.5 font-mono text-sm text-ink-primary outline-none focus:border-brand"
        />
        <button
          onClick={handleSave}
          disabled={pending || !value.trim()}
          className="rounded-sm bg-brand px-4 py-1.5 text-sm font-medium text-base hover:bg-brand-soft disabled:opacity-60"
        >
          {pending ? 'Saving…' : 'Save'}
        </button>
      </div>

      {error && <p className="text-xs text-signal-danger">{error}</p>}
      {saved && !error && <p className="text-xs text-signal-success">Saved. The Worker will pick it up within 5 minutes.</p>}
    </div>
  );
}
