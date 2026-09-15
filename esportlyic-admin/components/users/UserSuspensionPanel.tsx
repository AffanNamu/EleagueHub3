'use client';

import { useState } from 'react';
import { Ban, ShieldCheck } from 'lucide-react';
import { useUserSuspensionAction } from '@/hooks/useUserSuspensionAction';
import { formatRelativeTime } from '@/lib/utils';
import type { AdminUserProfile } from '@/types/user';

export function UserSuspensionPanel({ profile }: { profile: AdminUserProfile }) {
  const { submit, submitting, error } = useUserSuspensionAction(profile.userId);
  const [reason, setReason] = useState('');

  async function handleSuspend() {
    if (!reason.trim()) return;
    if (
      !confirm(
        `Suspend this account? This blocks sign-in immediately and force-signs them out of any active session. This is reversible.`,
      )
    ) {
      return;
    }
    const ok = await submit(true, reason);
    if (ok) setReason('');
  }

  async function handleReinstate() {
    if (!confirm('Reinstate this account? They will be able to sign in again immediately.')) return;
    await submit(false, '');
  }

  return (
    <div className="panel space-y-3 p-5">
      <h2 className="font-display text-sm font-semibold text-ink-primary">Account Suspension</h2>
      <p className="text-xs text-ink-secondary">
        Blocks sign-in platform-wide (not just chat) and force-signs out any active session — the
        strongest moderation action short of deleting the account.
      </p>

      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      {profile.suspended ? (
        <div className="space-y-3">
          <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2.5">
            <p className="flex items-center gap-2 text-sm font-medium text-signal-danger">
              <Ban size={14} /> Suspended
            </p>
            {profile.suspensionReason && <p className="mt-1 text-xs text-ink-secondary">{profile.suspensionReason}</p>}
            {profile.suspendedAtMs > 0 && (
              <p className="mt-1 text-xs text-ink-muted">{formatRelativeTime(profile.suspendedAtMs)}</p>
            )}
          </div>
          <button
            onClick={handleReinstate}
            disabled={submitting}
            className="flex w-full items-center justify-center gap-2 rounded-sm bg-signal-success py-2 text-sm font-medium text-base disabled:opacity-60"
          >
            <ShieldCheck size={15} /> Reinstate Account
          </button>
        </div>
      ) : (
        <div className="space-y-2">
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={2}
            placeholder="Reason (required, shown to the user)"
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-signal-danger"
          />
          <button
            onClick={handleSuspend}
            disabled={submitting || !reason.trim()}
            className="flex w-full items-center justify-center gap-2 rounded-sm bg-signal-danger py-2 text-sm font-medium text-white disabled:opacity-60"
          >
            <Ban size={15} /> Suspend Account
          </button>
        </div>
      )}
    </div>
  );
}
