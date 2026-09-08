import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { BreakdownCard } from '@/components/analytics/BreakdownCard';
import { CountryBreakdownCard } from '@/components/analytics/CountryBreakdownCard';
import { ShareChannelBreakdownCard } from '@/components/analytics/ShareChannelBreakdownCard';
import { TopSharedContentCard } from '@/components/analytics/TopSharedContentCard';
import {
  getPlanBreakdown,
  getOrganizerVerificationBreakdown,
  getLeagueFormatBreakdown,
  getUserCountryBreakdown,
} from '@/lib/repositories/analyticsAdminRepository';
import { getChannelBreakdown, getTopRollups } from '@/lib/repositories/linkAnalyticsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function AnalyticsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'analytics.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view analytics.</p>
      </div>
    );
  }

  const [
    planBreakdown,
    verificationBreakdown,
    formatBreakdown,
    countryBreakdown,
    channelBreakdown,
    mostShared,
    mostClicked,
  ] = await Promise.all([
    getPlanBreakdown(),
    getOrganizerVerificationBreakdown(),
    getLeagueFormatBreakdown(),
    getUserCountryBreakdown(),
    getChannelBreakdown(),
    getTopRollups({ sortBy: 'shareCount' }),
    getTopRollups({ sortBy: 'clickCount' }),
  ]);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Analytics' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Analytics</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Live breakdowns queried directly from Firestore.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <TopSharedContentCard title="Most Shared" rollups={mostShared} metric="shareCount" />
        <TopSharedContentCard title="Most Clicked" rollups={mostClicked} metric="clickCount" />
      </div>

      <ShareChannelBreakdownCard rows={channelBreakdown} />

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <CountryBreakdownCard data={countryBreakdown} />
        <BreakdownCard title="Organizer Verification Status" rows={verificationBreakdown} />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <BreakdownCard title="Users by Plan" rows={planBreakdown} />
        <BreakdownCard title="Leagues by Format" rows={formatBreakdown} />
      </div>
    </div>
  );
}
