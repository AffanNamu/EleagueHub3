import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { DiscussionsTable } from '@/components/moderation/DiscussionsTable';
import { listDiscussionThreads } from '@/lib/repositories/discussionsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function DiscussionsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'content.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view content.</p>
      </div>
    );
  }

  const threads = await listDiscussionThreads();
  const canModerate = hasPermission(identity, 'content.moderate');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Content' }, { label: 'Discussions' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Community Discussions</h1>
        <p className="mt-1 text-sm text-ink-secondary">Threads from the Discovery Hub's Community tab.</p>
      </div>
      <DiscussionsTable threads={threads} canModerate={canModerate} />
    </div>
  );
}
