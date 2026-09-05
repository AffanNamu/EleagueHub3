import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { PricingEditor } from '@/components/settings/PricingEditor';
import { getPricingConfig } from '@/lib/repositories/pricingConfigAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function PricingSettingsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'pricing.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view pricing.</p>
      </div>
    );
  }

  const config = await getPricingConfig();
  const canEdit = hasPermission(identity, 'pricing.edit');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Settings' }, { label: 'Pricing' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Pricing Configuration</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Editing the same app/pricing document the mobile app's pricing screen reads from. Changes take effect immediately.
        </p>
      </div>
      <PricingEditor config={config} canEdit={canEdit} />
    </div>
  );
}
