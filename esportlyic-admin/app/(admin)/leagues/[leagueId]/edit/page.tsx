import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { LeagueEditForm } from '@/components/leagues/LeagueEditForm';
import { getLeague } from '@/lib/repositories/leaguesAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function EditLeaguePage({ params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to manage leagues.</p>
      </div>
    );
  }

  const league = await getLeague(params.leagueId);
  if (!league) notFound();

  return (
    <div className="space-y-4">
      <Breadcrumbs
        items={[
          { label: 'Leagues', href: '/leagues' },
          { label: league.name || league.id, href: `/leagues/${league.id}` },
          { label: 'Edit' },
        ]}
      />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Edit League</h1>
      </div>
      <LeagueEditForm league={league} />
    </div>
  );
}
