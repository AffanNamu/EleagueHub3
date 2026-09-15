'use client';

import Image from 'next/image';
import Link from 'next/link';
import { Building2, Pencil, Trash2 } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { useOrganizerDelete } from '@/hooks/useOrganizerActions';
import { verificationStatusLabel, verificationStatusTone } from '@/lib/models/masterLeagueVerification';
import { formatRelativeTime } from '@/lib/utils';
import type { Organizer } from '@/types/organizer';

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="panel p-4">
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-1 font-display text-lg font-semibold text-ink-primary">{value}</p>
    </div>
  );
}

export function OrganizerDetailPanel({ organizer, canManage }: { organizer: Organizer; canManage: boolean }) {
  const socialEntries = Object.entries(organizer.socialLinks).filter(([, value]) => Boolean(value));
  const { remove, deleting, error } = useOrganizerDelete();

  return (
    <div className="space-y-4">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="panel p-5">
        <div className="flex items-start gap-4">
          {organizer.logoUrl ? (
            <Image
              src={organizer.logoUrl}
              alt={organizer.name}
              width={56}
              height={56}
              className="rounded-md border border-base-border object-cover"
            />
          ) : (
            <div className="flex h-14 w-14 items-center justify-center rounded-md bg-base-raised text-ink-muted">
              <Building2 size={22} />
            </div>
          )}
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <h1 className="font-display text-lg font-semibold text-ink-primary">{organizer.name || 'Untitled'}</h1>
              <Badge tone={verificationStatusTone(organizer.verificationStatus === 'none' ? 'pending' : organizer.verificationStatus)}>
                {organizer.verificationStatus === 'none' ? 'Not Verified' : verificationStatusLabel(organizer.verificationStatus)}
              </Badge>
              <Badge tone="brand" className="uppercase">{organizer.plan}</Badge>
            </div>
            {organizer.bio && <p className="mt-1.5 text-sm text-ink-secondary">{organizer.bio}</p>}
            <p className="mt-2 text-xs text-ink-muted">
              Owner: {organizer.ownerId} · {organizer.memberIds.length} member{organizer.memberIds.length === 1 ? '' : 's'}
              {organizer.country ? ` · ${organizer.country}` : ''}
            </p>
          </div>
          {canManage && (
            <div className="flex items-center gap-1">
              <Link
                href={`/organizers/${organizer.id}/edit`}
                className="rounded-sm p-2 text-ink-secondary hover:bg-base-raised hover:text-ink-primary"
                aria-label="Edit organizer workspace"
              >
                <Pencil size={16} />
              </Link>
              <button
                onClick={() => remove(organizer.id, organizer.name || organizer.id)}
                disabled={deleting}
                className="rounded-sm p-2 text-ink-secondary hover:bg-base-raised hover:text-signal-danger disabled:opacity-60"
                aria-label="Delete organizer workspace"
              >
                <Trash2 size={16} />
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Tournaments" value={organizer.totalTournamentsCreated} />
        <Stat label="Teams" value={organizer.totalParticipantsTeams} />
        <Stat label="Matches" value={organizer.totalMatches} />
        <Stat label="Followers" value={organizer.followersCount} />
      </div>

      {organizer.verifiedBadge && organizer.verificationExpiresAtMs > 0 && (
        <div className="panel p-5">
          <p className="text-sm text-ink-secondary">
            Verification expires {formatRelativeTime(organizer.verificationExpiresAtMs)}
          </p>
        </div>
      )}

      {socialEntries.length > 0 && (
        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Social Links</h2>
          <ul className="space-y-1">
            {socialEntries.map(([platform, url]) => (
              <li key={platform}>
                <a href={url} target="_blank" rel="noreferrer" className="text-sm text-brand hover:underline">
                  {platform}: {url}
                </a>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
