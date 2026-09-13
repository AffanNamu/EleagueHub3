import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { HomeContentForm } from '@/components/homeContent/HomeContentForm';
import { getHomeContent } from '@/lib/repositories/homeContentAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function EditHomeContentPage({ params }: { params: { id: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'home_content.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to manage home content.</p>
      </div>
    );
  }

  const item = await getHomeContent(params.id);
  if (!item) notFound();

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Content' }, { label: 'Home Content', href: '/content/home' }, { label: item.title }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Edit Home Content</h1>
      </div>
      <HomeContentForm existing={item} />
    </div>
  );
}
