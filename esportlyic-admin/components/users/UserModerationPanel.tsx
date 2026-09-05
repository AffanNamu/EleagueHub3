'use client';

import { Ban, MicOff, ShieldCheck } from 'lucide-react';
import { useUserModerationAction } from '@/hooks/useUserModerationAction';
import type { AdminUserProfile } from '@/types/user';

export function UserModerationPanel({ profile }: { profile: AdminUserProfile }) {
  const { submit, submitting, error } = useUserModerationAction(profile.userId);

  return (
    <div className="panel space-y-3 p-5">
      <h2 className="font-display text-sm font-semibold text-ink-primary">Chat Moderation</h2>
      <p className="text-xs text-ink-secondary">
        Mute/ban and Global Chat admin status are Super-Admin-only on mobile — actions here go
        through the web workspace's own permission check instead.
      </p>

      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="space-y-2">
        <button
          onClick={() => submit({ muted: !profile.chatMuted, banned: profile.chatBanned })}
          disabled={submitting}
          className="flex w-full items-center justify-between rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm disabled:opacity-60"
        >
          <span className="flex items-center gap-2 text-ink-primary">
            <MicOff size={15} /> Mute from Chat
          </span>
          <span className={profile.chatMuted ? 'text-signal-warning' : 'text-ink-muted'}>
            {profile.chatMuted ? 'Muted' : 'Not muted'}
          </span>
        </button>

        <button
          onClick={() => submit({ muted: profile.chatMuted, banned: !profile.chatBanned })}
          disabled={submitting}
          className="flex w-full items-center justify-between rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm disabled:opacity-60"
        >
          <span className="flex items-center gap-2 text-ink-primary">
            <Ban size={15} /> Ban from Chat
          </span>
          <span className={profile.chatBanned ? 'text-signal-danger' : 'text-ink-muted'}>
            {profile.chatBanned ? 'Banned' : 'Not banned'}
          </span>
        </button>

        <button
          onClick={() => submit({ isGlobalChatAdmin: !profile.isGlobalChatAdmin })}
          disabled={submitting}
          className="flex w-full items-center justify-between rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm disabled:opacity-60"
        >
          <span className="flex items-center gap-2 text-ink-primary">
            <ShieldCheck size={15} /> Global Chat Moderator
          </span>
          <span className={profile.isGlobalChatAdmin ? 'text-signal-success' : 'text-ink-muted'}>
            {profile.isGlobalChatAdmin ? 'Enabled' : 'Disabled'}
          </span>
        </button>
      </div>
    </div>
  );
}
