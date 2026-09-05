import { notFound } from 'next/navigation';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { UserDetailPanel } from '@/components/users/UserDetailPanel';
import { getUserDetail } from '@/lib/repositories/usersAdminRepository';
import { getPaymentsForUser } from '@/lib/repositories/paymentsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function UserDetailPage({ params }: { params: { userId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'users.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view users.</p>
      </div>
    );
  }

  const profile = await getUserDetail(params.userId);
  if (!profile) notFound();

  const canViewPayments = hasPermission(identity, 'payments.view');
  const payments = canViewPayments ? await getPaymentsForUser(params.userId) : [];

  const canModerate = hasPermission(identity, 'users.moderate');
  const canOverrideEntitlement = identity?.isSuperAdmin === true;

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Users', href: '/users' }, { label: profile.teamName || profile.userId }]} />
      <UserDetailPanel
        profile={profile}
        payments={payments}
        canModerate={canModerate}
        canOverrideEntitlement={canOverrideEntitlement}
        canViewPayments={canViewPayments}
      />
    </div>
  );
}
