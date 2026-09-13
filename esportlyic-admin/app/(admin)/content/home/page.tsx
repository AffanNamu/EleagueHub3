import Link from 'next/link';
import { Plus } from 'lucide-react';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { HomeContentTable } from '@/components/homeContent/HomeContentTable';
import { listHomeContent } from '@/lib/repositories/homeContentAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function HomeContentPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'home_content.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view home content.</p>
      </div>
    );
  }

  const items = await listHomeContent();
  const canManage = hasPermission(identity, 'home_content.manage');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Content' }, { label: 'Home Content' }]} />
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-xl font-semibold text-ink-primary">Home Content</h1>
          <p className="mt-1 text-sm text-ink-secondary">
            Hero banners, promo cards, and announcements shown on the app and web home screen.
          </p>
        </div>
        {canManage && (
          <Link
            href="/content/home/new"
            className="flex items-center gap-2 rounded-sm bg-brand px-3.5 py-2 text-sm font-medium text-white hover:bg-brand-soft"
          >
            <Plus size={15} /> New
          </Link>
        )}
      </div>
      <HomeContentTable items={items} canManage={canManage} />
    </div>
  );
}
