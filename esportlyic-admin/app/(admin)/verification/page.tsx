import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { VerificationFilterTabs } from '@/components/verification/VerificationFilterTabs';
import { VerificationQueueTable } from '@/components/verification/VerificationQueueTable';
import { listVerificationRequests } from '@/lib/repositories/verificationAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import type { VerificationStatus } from '@/types/verification';

export const dynamic = 'force-dynamic';

const VALID_STATUSES: VerificationStatus[] = ['pending', 'approved', 'rejected', 'info_requested'];

export default async function VerificationQueuePage({
  searchParams,
}: {
  searchParams: { status?: string };
}) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'verification.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view verification requests.</p>
      </div>
    );
  }

  const statusParam = searchParams.status;
  const statusFilter = VALID_STATUSES.includes(statusParam as VerificationStatus)
    ? (statusParam as VerificationStatus)
    : 'pending';

  const requests = await listVerificationRequests(
    searchParams.status === 'all' ? undefined : statusFilter,
  );

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Verification' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Organizer Verification</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Review organizer workspace applications for the verified badge.
        </p>
      </div>
      <VerificationFilterTabs />
      <VerificationQueueTable requests={requests} />
    </div>
  );
}
