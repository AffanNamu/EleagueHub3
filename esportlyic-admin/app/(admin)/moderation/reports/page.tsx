import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { ReportsFilterTabs } from '@/components/moderation/ReportsFilterTabs';
import { ReportsTable } from '@/components/moderation/ReportsTable';
import { listReports } from '@/lib/repositories/reportsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import type { ReportStatus } from '@/types/report';

export const dynamic = 'force-dynamic';

const VALID_STATUSES: ReportStatus[] = ['pending', 'reviewed', 'dismissed'];

export default async function ReportsPage({ searchParams }: { searchParams: { status?: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'reports.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view reports.</p>
      </div>
    );
  }

  const statusParam = searchParams.status;
  const statusFilter = VALID_STATUSES.includes(statusParam as ReportStatus)
    ? (statusParam as ReportStatus)
    : 'pending';

  const reports = await listReports(searchParams.status === 'all' ? undefined : statusFilter);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Moderation' }, { label: 'Reports' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">User Reports</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          The first-ever review interface for this collection — mobile only submits reports.
        </p>
      </div>
      <ReportsFilterTabs />
      <ReportsTable reports={reports} />
    </div>
  );
}
