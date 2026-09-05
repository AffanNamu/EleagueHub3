import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { SearchBar } from '@/components/ui/SearchBar';
import { LeaguesTable } from '@/components/leagues/LeaguesTable';
import { listLeagues } from '@/lib/repositories/leaguesAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function LeaguesPage({ searchParams }: { searchParams: { q?: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view leagues.</p>
      </div>
    );
  }

  const leagues = await listLeagues({ search: searchParams.q });

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Leagues' }]} />
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">Leagues</h1>
          <p className="mt-1 text-sm text-ink-secondary">
            All competitions across the platform, standalone and organizer-run.
          </p>
        </div>
        <SearchBar placeholder="Search by name…" />
      </div>
      <LeaguesTable leagues={leagues} />
    </div>
  );
}
