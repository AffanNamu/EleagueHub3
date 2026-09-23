import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { AppUpdateEditor } from '@/components/settings/AppUpdateEditor';
import { getAppUpdateConfig } from '@/lib/repositories/appUpdateAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function AppUpdatesSettingsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view this page.</p>
      </div>
    );
  }

  const config = await getAppUpdateConfig();
  const canEdit = hasPermission(identity, 'settings.manage');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Settings', href: '/settings' }, { label: 'App Updates' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">App Updates</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Editing app_config/app_update — the mobile app only (this never affects the web version).
          Set the latest build here whenever you ship a new mobile release. Leave &quot;Force this
          update&quot; off for a dismissible nudge, or turn it on to block the app entirely until
          users update.
        </p>
      </div>
      <AppUpdateEditor config={config} canEdit={canEdit} />
    </div>
  );
}
