import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { SendNotificationForm } from '@/components/notifications/SendNotificationForm';
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
    </div>
  );
}
