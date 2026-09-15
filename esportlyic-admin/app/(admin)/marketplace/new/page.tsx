import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { MarketplaceProductForm } from '@/components/marketplace/MarketplaceProductForm';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function NewMarketplaceProductPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'marketplace.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to manage the marketplace.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Marketplace', href: '/marketplace' }, { label: 'New' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">New Marketplace Listing</h1>
      </div>
      <MarketplaceProductForm />
    </div>
  );
}
