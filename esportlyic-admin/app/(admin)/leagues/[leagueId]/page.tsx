import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { LeagueDetailPanel } from '@/components/leagues/LeagueDetailPanel';
import { LeagueMatchesSection } from '@/components/leagues/LeagueMatchesSection';
import { getLeague } from '@/lib/repositories/leaguesAdminRepository';
import {
  listFixtureMatches,
  listKnockoutMatches,
  listPointAdjustments,
} from '@/lib/repositories/matchesAdminRepository';
import { listTeamsForLeague } from '@/lib/repositories/teamsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function LeagueDetailPage({ params }: { params: { leagueId: string } }) {
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

  const [fixtures, knockout, teams, adjustments] = await Promise.all([
    listFixtureMatches(params.leagueId),
    listKnockoutMatches(params.leagueId),
    listTeamsForLeague(params.leagueId),
    listPointAdjustments(params.leagueId),
  ]);

  const canManage = hasPermission(identity, 'leagues.manage');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Leagues', href: '/leagues' }, { label: league.name || league.id }]} />
      <LeagueDetailPanel league={league} />
      <LeagueMatchesSection
        leagueId={params.leagueId}
        fixtures={fixtures}
        knockout={knockout}
        teams={teams}
        adjustments={adjustments}
        canManage={canManage}
      />
    </div>
  );
}
