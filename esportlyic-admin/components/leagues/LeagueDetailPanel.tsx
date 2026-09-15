'use client';

import Link from 'next/link';
import { Trophy, Lock, Globe, ScrollText, ChevronRight, Pencil, Trash2 } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { useLeagueDelete } from '@/hooks/useLeagueActions';
import { leagueFormatLabel } from '@/types/league';
import { formatRelativeTime } from '@/lib/utils';
import type { League } from '@/types/league';

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs text-ink-muted">{label}</p>
      <div className="mt-0.5 text-sm text-ink-primary">{value}</div>
    </div>
  );
}

export function LeagueDetailPanel({ league, canManage }: { league: League; canManage: boolean }) {
  const { remove, deleting, error } = useLeagueDelete();

  return (
    <div className="space-y-4">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="panel p-5">
        <div className="flex items-start gap-4">
          <div className="flex h-14 w-14 items-center justify-center rounded-md bg-base-raised text-ink-muted">
            <Trophy size={22} />
          </div>
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <h1 className="font-display text-lg font-semibold text-ink-primary">{league.name || 'Untitled'}</h1>
              {league.isPrivate ? (
                <Badge tone="warning" className="inline-flex items-center gap-1">
                  <Lock size={11} /> Private
                </Badge>
              ) : (
                <Badge tone="success" className="inline-flex items-center gap-1">
                  <Globe size={11} /> Public
                </Badge>
              )}
            </div>
            <p className="mt-1 text-sm text-ink-secondary">{leagueFormatLabel(league.format)}</p>
            {league.description && <p className="mt-2 text-sm text-ink-secondary">{league.description}</p>}
          </div>
          {canManage && (
            <div className="flex items-center gap-1">
              <Link
                href={`/leagues/${league.id}/edit`}
                className="rounded-sm p-2 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
                aria-label="Edit league"
              >
                <Pencil size={16} />
              </Link>
              <button
                onClick={() => remove(league.id, league.name || league.id)}
                disabled={deleting}
                className="rounded-sm p-2 text-ink-secondary hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
                aria-label="Delete league"
              >
                <Trash2 size={16} />
              </button>
            </div>
          )}
        </div>
      </div>

      <Link
        href={`/leagues/${league.id}/rules`}
        className="panel flex items-center gap-3 p-4 transition-colors hover:border-brand/40"
      >
        <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-md bg-brand-faint text-brand">
          <ScrollText size={17} />
        </div>
        <div className="flex-1">
          <p className="text-sm font-medium text-ink-primary">Competition Rules</p>
          <p className="text-xs text-ink-secondary">Scheduling, match settings, disputes, and more</p>
        </div>
        <ChevronRight size={16} className="text-ink-muted" />
      </Link>

      <div className="panel grid grid-cols-2 gap-4 p-5 sm:grid-cols-3">
        <Field label="Max Teams" value={league.maxTeams || '—'} />
        <Field label="Members" value={league.memberCount} />
        <Field label="Football Category" value={league.footballCategory || '—'} />
        <Field label="Coupons Enabled" value={league.couponsEnabled ? 'Yes' : 'No'} />
        <Field label="Created" value={league.createdAtMs ? formatRelativeTime(league.createdAtMs) : '—'} />
        <Field
          label="Organizer Workspace"
          value={
            league.masterLeagueId ? (
              <Link href={`/organizers/${league.masterLeagueId}`} className="text-brand hover:underline">
                {league.masterLeagueId}
              </Link>
            ) : (
              'Standalone (no workspace)'
            )
          }
        />
      </div>

      <div className="panel p-5">
        <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Ownership</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Field label="Organizer UID" value={league.organizerUid || '—'} />
          <Field label="Owner UID" value={league.ownerUid || '—'} />
        </div>
      </div>
    </div>
  );
}
