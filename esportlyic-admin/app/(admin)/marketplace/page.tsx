import Link from 'next/link';
import { Plus } from 'lucide-react';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { MarketplaceProductTable } from '@/components/marketplace/MarketplaceProductTable';
import { listMarketplaceProducts } from '@/lib/repositories/marketplaceAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function MarketplacePage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'marketplace.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view the marketplace.</p>
      </div>
    );
  }

  const items = await listMarketplaceProducts();
  const canManage = hasPermission(identity, 'marketplace.manage');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Marketplace' }]} />
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">Marketplace</h1>
          <p className="mt-1 text-sm text-ink-secondary">
            Affiliate product listings shown in the app/web Marketplace tab.
          </p>
        </div>
        {canManage && (
          <Link
            href="/marketplace/new"
            className="flex items-center gap-2 rounded-sm bg-brand px-3.5 py-2 text-sm font-medium text-base hover:bg-brand-soft"
          >
            <Plus size={15} /> New Listing
          </Link>
        )}
      </div>
      <MarketplaceProductTable items={items} canManage={canManage} />
    </div>
  );
}
