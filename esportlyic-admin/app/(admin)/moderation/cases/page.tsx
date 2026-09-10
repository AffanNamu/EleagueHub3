import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { CasesTable } from '@/components/moderation/CasesTable';
import { listCases } from '@/lib/repositories/moderationCasesAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function CasesPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'moderation_cases.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view moderation cases.</p>
      </div>
    );
  }

  const cases = await listCases();

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Moderation' }, { label: 'Cases' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Moderation Cases</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Investigations grouping reports, content, and chat incidents against a user.
        </p>
      </div>
      <CasesTable cases={cases} />
    </div>
  );
}
