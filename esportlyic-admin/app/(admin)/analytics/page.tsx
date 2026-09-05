import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { BreakdownCard } from '@/components/analytics/BreakdownCard';
import {
  getPlanBreakdown,
  getOrganizerVerificationBreakdown,
  getLeagueFormatBreakdown,
} from '@/lib/repositories/analyticsAdminRepository';
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

  const [planBreakdown, verificationBreakdown, formatBreakdown] = await Promise.all([
    getPlanBreakdown(),
    getOrganizerVerificationBreakdown(),
    getLeagueFormatBreakdown(),
  ]);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Analytics' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Analytics</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Live breakdowns queried directly from Firestore — no scheduled rollup exists yet, so these reflect the current moment, not historical trends.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <BreakdownCard title="Users by Plan" rows={planBreakdown} />
        <BreakdownCard title="Organizer Verification Status" rows={verificationBreakdown} />
        <BreakdownCard title="Leagues by Format" rows={formatBreakdown} />
      </div>
    </div>
  );
}
