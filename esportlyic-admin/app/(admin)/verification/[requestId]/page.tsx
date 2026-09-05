import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { VerificationReviewPanel } from '@/components/verification/VerificationReviewPanel';
import { getVerificationRequest } from '@/lib/repositories/verificationAdminRepository';
import { getMasterLeagueSummary, getOwnerProfileSummary } from '@/lib/repositories/masterLeaguesAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function VerificationRequestPage({
  params,
}: {
  params: { requestId: string };
}) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'verification.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view verification requests.</p>
      </div>
    );
  }

  const request = await getVerificationRequest(params.requestId);
  if (!request) notFound();

  const [masterLeague, owner] = await Promise.all([
    getMasterLeagueSummary(request.masterLeagueId),
    getOwnerProfileSummary(request.ownerId),
  ]);

  const canReview = hasPermission(identity, 'verification.review');

  return (
    <div className="space-y-4">
      <Breadcrumbs
        items={[{ label: 'Verification', href: '/verification' }, { label: request.requestId }]}
      />
      <VerificationReviewPanel request={request} masterLeague={masterLeague} owner={owner} canReview={canReview} />
    </div>
  );
}
