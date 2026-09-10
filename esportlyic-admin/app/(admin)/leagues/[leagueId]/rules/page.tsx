import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { CompetitionRulesEditor } from '@/components/leagues/CompetitionRulesEditor';
import { getLeague } from '@/lib/repositories/leaguesAdminRepository';
import { getCompetitionRules } from '@/lib/repositories/competitionRulesAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function CompetitionRulesPage({ params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view leagues.</p>
      </div>
    );
  }

  const league = await getLeague(params.leagueId);
  if (!league) notFound();

  const rules = await getCompetitionRules(params.leagueId);
  const canManage = hasPermission(identity, 'leagues.manage');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Leagues', href: '/leagues' }, { label: league.name || league.id, href: `/leagues/${league.id}` }, { label: 'Competition Rules' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Competition Rules</h1>
        <p className="mt-1 text-sm text-ink-secondary">{league.name}</p>
      </div>
      <CompetitionRulesEditor leagueId={params.leagueId} initialRules={rules} canManage={canManage} />
    </div>
  );
}
