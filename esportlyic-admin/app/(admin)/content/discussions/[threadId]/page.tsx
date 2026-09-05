import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { DiscussionDetailPanel } from '@/components/moderation/DiscussionDetailPanel';
import { getDiscussionThread, listDiscussionReplies } from '@/lib/repositories/discussionsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function DiscussionDetailPage({ params }: { params: { threadId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'content.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view content.</p>
      </div>
    );
  }

  const thread = await getDiscussionThread(params.threadId);
  if (!thread) notFound();

  const replies = await listDiscussionReplies(params.threadId);
  const canModerate = hasPermission(identity, 'content.moderate');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Content' }, { label: 'Discussions', href: '/content/discussions' }, { label: thread.title }]} />
      <DiscussionDetailPanel thread={thread} replies={replies} canModerate={canModerate} />
    </div>
  );
}
