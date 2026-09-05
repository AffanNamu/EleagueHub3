import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { AuditLogTable } from '@/components/audit/AuditLogTable';
import { listAuditLogs } from '@/lib/audit/auditLog';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function AuditLogsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'audit_logs.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view the audit log.</p>
      </div>
    );
  }

  const entries = await listAuditLogs();

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Audit Logs' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Audit Log</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Every action taken through this workspace, in order.
        </p>
      </div>
      <AuditLogTable entries={entries} />
    </div>
  );
}
