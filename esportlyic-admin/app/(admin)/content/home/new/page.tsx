import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { HomeContentForm } from '@/components/homeContent/HomeContentForm';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function NewHomeContentPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'home_content.manage')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to manage home content.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Content' }, { label: 'Home Content', href: '/content/home' }, { label: 'New' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">New Home Content</h1>
      </div>
      <HomeContentForm />
    </div>
  );
}
