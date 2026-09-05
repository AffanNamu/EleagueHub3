import Link from 'next/link';
import Image from 'next/image';
import { Building2 } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { verificationStatusLabel, verificationStatusTone } from '@/lib/models/masterLeagueVerification';
import type { Organizer } from '@/types/organizer';

const PLAN_TONE: Record<Organizer['plan'], 'neutral' | 'brand' | 'success'> = {
  basic: 'neutral',
  pro: 'brand',
  elite: 'success',
};

export function OrganizersTable({ organizers }: { organizers: Organizer[] }) {
  if (organizers.length === 0) {
    return (
      <EmptyState
        icon={Building2}
        title="No organizer workspaces found"
        description="Try a different search term, or check back once organizers create workspaces."
      />
    );
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">Organizer</th>
            <th className="px-4 py-3 font-medium">Plan</th>
            <th className="px-4 py-3 font-medium">Verification</th>
            <th className="px-4 py-3 font-medium">Tournaments</th>
            <th className="px-4 py-3 font-medium">Followers</th>
          </tr>
        </thead>
        <tbody>
          {organizers.map((organizer) => (
            <tr key={organizer.id} className="border-b border-base-border last:border-0 hover:bg-base-raised">
              <td className="px-4 py-3">
                <Link href={`/organizers/${organizer.id}`} className="flex items-center gap-3">
                  {organizer.logoUrl ? (
                    <Image
                      src={organizer.logoUrl}
                      alt={organizer.name}
                      width={32}
                      height={32}
                      className="rounded-sm border border-base-border object-cover"
                    />
                  ) : (
                    <div className="flex h-8 w-8 items-center justify-center rounded-sm bg-base-raised text-xs text-ink-muted">
                      <Building2 size={14} />
                    </div>
                  )}
                  <div>
                    <p className="font-medium text-ink-primary">{organizer.name || 'Untitled'}</p>
                    <p className="text-xs text-ink-muted">{organizer.id}</p>
                  </div>
                </Link>
              </td>
              <td className="px-4 py-3">
                <Badge tone={PLAN_TONE[organizer.plan]} className="uppercase">
                  {organizer.plan}
                </Badge>
              </td>
              <td className="px-4 py-3">
                <Badge tone={verificationStatusTone(organizer.verificationStatus === 'none' ? 'pending' : organizer.verificationStatus)}>
                  {organizer.verificationStatus === 'none' ? 'Not Verified' : verificationStatusLabel(organizer.verificationStatus)}
                </Badge>
              </td>
              <td className="px-4 py-3 text-ink-secondary">{organizer.totalTournamentsCreated}</td>
              <td className="px-4 py-3 text-ink-secondary">{organizer.followersCount}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
