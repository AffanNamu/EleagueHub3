import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { SendNotificationForm } from '@/components/notifications/SendNotificationForm';
import { RecentNotifications } from '@/components/notifications/RecentNotifications';
import { listAuditLogsByAction } from '@/lib/audit/auditLog';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function NotificationsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'notifications.send')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to send notifications.</p>
      </div>
    );
  }

  let recentSends: Awaited<ReturnType<typeof listAuditLogsByAction>> = [];
  try {
    recentSends = await listAuditLogsByAction('notification.send');
  } catch (err) {
    // Don't let a missing/still-building audit_logs index take down the
    // whole Send Notification page -- the form itself doesn't depend on
    // this history list.
    console.error('[NotificationsPage] listAuditLogsByAction failed', err);
  }

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Notifications' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Send Notification</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Delivered via Firebase Cloud Messaging to registered devices. Every send is logged.
        </p>
      </div>
      <SendNotificationForm />
      <RecentNotifications entries={recentSends} />
    </div>
  );
}
