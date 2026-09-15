import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { LeagueCouponsPanel } from '@/components/leagues/LeagueCouponsPanel';
import { getLeague } from '@/lib/repositories/leaguesAdminRepository';
import {
  getCouponConfig,
  listCouponCodes,
  listCouponRedemptions,
} from '@/lib/repositories/couponsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function LeagueCouponsPage({ params }: { params: { leagueId: string } }) {
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

  const [config, codes, redemptions] = await Promise.all([
    getCouponConfig(params.leagueId),
    listCouponCodes(params.leagueId),
    listCouponRedemptions(params.leagueId),
  ]);

  return (
    <div className="space-y-4">
      <Breadcrumbs
        items={[
          { label: 'Leagues', href: '/leagues' },
          { label: league.name || league.id, href: `/leagues/${league.id}` },
          { label: 'Coupons' },
        ]}
      />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Coupon Codes</h1>
      </div>
      <LeagueCouponsPanel
        leagueId={params.leagueId}
        couponsEnabled={league.couponsEnabled}
        config={config}
        codes={codes}
        redemptions={redemptions}
        canManage={hasPermission(identity, 'leagues.manage')}
      />
    </div>
  );
}
