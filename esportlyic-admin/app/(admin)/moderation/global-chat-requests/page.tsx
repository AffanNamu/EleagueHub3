import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { GlobalChatRequestsFilterTabs } from '@/components/moderation/GlobalChatRequestsFilterTabs';
import { GlobalChatRequestsTable } from '@/components/moderation/GlobalChatRequestsTable';
import { listGlobalChatRequests } from '@/lib/repositories/globalChatRequestsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { DEFAULT_GLOBAL_CHAT_TAB, type GlobalChatRequestStatus } from '@/types/globalChatRequest';

export const dynamic = 'force-dynamic';

const VALID_STATUSES: GlobalChatRequestStatus[] = ['pending', 'approved', 'rejected'];

export default async function GlobalChatRequestsPage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'global_chat_requests.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view Global Chat members.</p>
      </div>
    );
  }

  const statusParam = searchParams.status;
  const statusFilter = VALID_STATUSES.includes(statusParam as GlobalChatRequestStatus)
    ? (statusParam as GlobalChatRequestStatus)
    : DEFAULT_GLOBAL_CHAT_TAB;

  const requests = await listGlobalChatRequests(searchParams.status === 'all' ? undefined : statusFilter);
  const canReview = hasPermission(identity, 'global_chat_requests.review');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Moderation' }, { label: 'Global Chat Members' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Global Chat Members</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Users join Global Chat themselves by tapping Join (no approval since 22 Nov 2026).
          Remove someone to stop them reading and sending in Global Chat; they can&apos;t re-join
          until an admin restores them. &quot;Pending&quot; only lists requests made before the change.
        </p>
      </div>
      <GlobalChatRequestsFilterTabs />
      <GlobalChatRequestsTable requests={requests} canReview={canReview} />
    </div>
  );
}
