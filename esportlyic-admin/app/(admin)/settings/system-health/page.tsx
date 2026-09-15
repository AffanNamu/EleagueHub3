import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { SystemAlerts } from '@/components/dashboard/SystemAlerts';
import { BuildInfoPanel } from '@/components/settings/BuildInfoPanel';
import { getDashboardStats, getSystemHealthAlerts } from '@/lib/repositories/dashboardRepository';
import { getBuildInfo } from '@/lib/buildInfo';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

function QueueStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="panel p-4">
      <p className="text-xs text-ink-muted">{label}</p>
      <p className="mt-1 font-display text-lg font-semibold text-ink-primary">{value}</p>
    </div>
  );
}

export default async function SystemHealthPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view system settings.</p>
      </div>
    );
  }

  const [alerts, stats] = await Promise.all([getSystemHealthAlerts(), getDashboardStats()]);
  const buildInfo = getBuildInfo();

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Settings', href: '/settings' }, { label: 'System Health' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">System Health</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Live backlog signals and build info — there's no automated alerting pipeline behind this,
          everything here is computed directly from Firestore and this deployment's own files on
          every page load.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <QueueStat label="Pending Reports" value={stats.pendingReports} />
        <QueueStat label="Pending Verifications" value={stats.pendingVerifications} />
        <QueueStat label="Pending Chat Requests" value={stats.pendingGlobalChatRequests} />
      </div>

      <SystemAlerts alerts={alerts} />
      <BuildInfoPanel info={buildInfo} />
    </div>
  );
}
