import Link from 'next/link';
import { Trophy, Lock, Globe } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
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

export function LeagueDetailPanel({ league }: { league: League }) {
  return (
    <div className="space-y-4">
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
          </div>
        </div>
      </div>

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
