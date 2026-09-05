import Image from 'next/image';
import { Building2 } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
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

export function OrganizerDetailPanel({ organizer }: { organizer: Organizer }) {
  const socialEntries = Object.entries(organizer.socialLinks).filter(([, value]) => Boolean(value));

  return (
    <div className="space-y-4">
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
