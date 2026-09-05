import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { PaymentsTable } from '@/components/payments/PaymentsTable';
import { RevenueSummaryCard } from '@/components/payments/RevenueSummaryCard';
import { listPayments, getRevenueSummary } from '@/lib/repositories/paymentsAdminRepository';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function PaymentsPage() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'payments.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view payments.</p>
      </div>
    );
  }

  const [payments, revenueSummary] = await Promise.all([listPayments(), getRevenueSummary()]);

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Payments' }]} />
      <div>
        <h1 className="font-display text-xl font-semibold text-ink-primary">Payments</h1>
        <p className="mt-1 text-sm text-ink-secondary">
          Read-only payment history. Every row here is a successful, immutable-status transaction.
        </p>
      </div>
      <RevenueSummaryCard summary={revenueSummary} />
      <PaymentsTable payments={payments} />
    </div>
  );
}
