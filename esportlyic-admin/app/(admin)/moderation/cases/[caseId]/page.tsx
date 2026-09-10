import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { CaseDetailPanel } from '@/components/moderation/CaseDetailPanel';
import { getCase } from '@/lib/repositories/moderationCasesAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function CaseDetailPage({ params }: { params: { caseId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'moderation_cases.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view moderation cases.</p>
      </div>
    );
  }

  const caseData = await getCase(params.caseId);
  if (!caseData) notFound();

  const canManage = hasPermission(identity, 'moderation_cases.manage');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Moderation' }, { label: 'Cases', href: '/moderation/cases' }, { label: caseData.targetUserName || caseData.caseId }]} />
      <CaseDetailPanel caseData={caseData} canManage={canManage} />
    </div>
  );
}
