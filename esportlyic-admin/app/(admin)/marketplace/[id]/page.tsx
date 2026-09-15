import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { MarketplaceProductForm } from '@/components/marketplace/MarketplaceProductForm';
import { getMarketplaceProduct } from '@/lib/repositories/marketplaceAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function EditMarketplaceProductPage({ params }: { params: { id: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'marketplace.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to manage the marketplace.</p>
      </div>
    );
  }

  const item = await getMarketplaceProduct(params.id);
  if (!item) notFound();

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Marketplace', href: '/marketplace' }, { label: item.name }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Edit Listing</h1>
      </div>
      <MarketplaceProductForm existing={item} />
    </div>
  );
}
