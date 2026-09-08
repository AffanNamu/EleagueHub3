'use client';

import { useState } from 'react';
import { Send, CheckCircle2 } from 'lucide-react';
import { useSendNotification } from '@/hooks/useSendNotification';
import type { NotificationSegment } from '@/types/notification';

export function SendNotificationForm() {
  const { send, submitting, error, result } = useSendNotification();
  const [segment, setSegment] = useState<NotificationSegment>('all');
  const [leagueId, setLeagueId] = useState('');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [postToHomeScreen, setPostToHomeScreen] = useState(true);

  async function handleSubmit() {
    if (!confirm(`Send this notification to segment "${segment}"? This cannot be undone.`)) return;
    await send({
      segment,
      leagueId: segment === 'league' ? leagueId : undefined,
      title,
      body,
      postToHomeScreen: segment === 'all' && postToHomeScreen,
    });
  }

  return (
    <div className="panel space-y-4 p-5">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      {result && (
        <div className="flex items-start gap-2 rounded-sm border border-signal-success/40 bg-signal-successFaint px-3 py-2.5">
          <CheckCircle2 size={15} className="mt-0.5 flex-shrink-0 text-signal-success" />
          <p className="text-sm text-ink-secondary">
            Delivered to <span className="font-medium text-ink-primary">{result.successCount}</span> of{' '}
            {result.tokensFound} device(s) across {result.targetedUsers} targeted user(s).
            {result.failureCount > 0 && ` ${result.failureCount} failed (likely stale/uninstalled tokens).`}
            {result.postedToHomeScreen && ' Also posted as a home screen banner.'}
          </p>
        </div>
      )}

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">Audience</label>
        <select
          value={segment}
          onChange={(event) => setSegment(event.target.value as NotificationSegment)}
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        >
          <option value="all">All Users</option>
          <option value="pro">Pro Users</option>
          <option value="elite">Elite Users</option>
          <option value="league">Specific League</option>
        </select>
      </div>

      {segment === 'league' && (
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">League ID</label>
          <input
            value={leagueId}
            onChange={(event) => setLeagueId(event.target.value)}
            placeholder="Find this on the league's detail page URL"
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>
      )}

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">Title</label>
        <input
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          maxLength={120}
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        />
      </div>

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">Message</label>
        <textarea
          value={body}
          onChange={(event) => setBody(event.target.value)}
          maxLength={500}
          rows={4}
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        />
      </div>

      {segment === 'all' && (
        <label className="flex cursor-pointer items-start gap-2.5 rounded-sm bg-base-raised px-3 py-2.5">
          <input
            type="checkbox"
            checked={postToHomeScreen}
            onChange={(event) => setPostToHomeScreen(event.target.checked)}
            className="mt-0.5 h-4 w-4 rounded-sm border-base-border bg-base text-brand focus:ring-brand"
          />
          <div>
            <p className="text-sm text-ink-primary">Also post as a home screen banner</p>
            <p className="text-xs text-ink-secondary">
              Push notifications alone may not show while a user has the app open. This posts a
              persistent banner every user sees, closing that gap.
            </p>
          </div>
        </label>
      )}

      <button
        onClick={handleSubmit}
        disabled={submitting || !title.trim() || !body.trim() || (segment === 'league' && !leagueId.trim())}
        className="flex items-center gap-2 rounded-sm bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
      >
        <Send size={15} /> {submitting ? 'Sending…' : 'Send Notification'}
      </button>
    </div>
  );
}
