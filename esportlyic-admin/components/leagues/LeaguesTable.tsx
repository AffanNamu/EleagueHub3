import Link from 'next/link';
import { Trophy, Lock } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { leagueFormatLabel } from '@/types/league';
import type { League } from '@/types/league';

export function LeaguesTable({ leagues }: { leagues: League[] }) {
  if (leagues.length === 0) {
    return (
      <EmptyState
        icon={Trophy}
        title="No leagues found"
        description="Try a different search term, or check back once leagues are created."
      />
    );
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">League</th>
            <th className="px-4 py-3 font-medium">Format</th>
            <th className="px-4 py-3 font-medium">Members</th>
            <th className="px-4 py-3 font-medium">Organizer Workspace</th>
            <th className="px-4 py-3 font-medium">Visibility</th>
          </tr>
        </thead>
        <tbody>
          {leagues.map((league) => (
            <tr key={league.id} className="border-b border-base-border last:border-0 hover:bg-base-raised">
              <td className="px-4 py-3">
                <Link href={`/leagues/${league.id}`}>
                  <p className="font-medium text-ink-primary">{league.name || 'Untitled'}</p>
                  <p className="text-xs text-ink-muted">{league.id}</p>
                </Link>
              </td>
              <td className="px-4 py-3 text-ink-secondary">{leagueFormatLabel(league.format)}</td>
              <td className="px-4 py-3 text-ink-secondary">{league.memberCount}</td>
              <td className="px-4 py-3">
                {league.masterLeagueId ? (
                  <Link href={`/organizers/${league.masterLeagueId}`} className="text-brand hover:underline">
                    View workspace
                  </Link>
                ) : (
                  <span className="text-ink-muted">Standalone</span>
                )}
              </td>
              <td className="px-4 py-3">
                {league.isPrivate ? (
                  <Badge tone="warning" className="inline-flex items-center gap-1">
                    <Lock size={11} /> Private
                  </Badge>
                ) : (
                  <Badge tone="success">Public</Badge>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
