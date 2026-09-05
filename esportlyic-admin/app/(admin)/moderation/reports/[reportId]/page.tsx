import { notFound } from 'next/navigation';
import Link from 'next/link';
import { Breadcrumbs } from '@/components/layout/Breadcrumbs';
import { Badge } from '@/components/ui/Badge';
import { getReport } from '@/lib/repositories/reportsAdminRepository';
import { getUserSummary } from '@/lib/repositories/usersAdminRepository';
import { reportReasonLabel } from '@/types/report';
import { formatRelativeTime } from '@/lib/utils';
import { ReportReviewActions } from '@/components/moderation/ReportReviewActions';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';

export const dynamic = 'force-dynamic';

export default async function ReportDetailPage({ params }: { params: { reportId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'reports.view')) {
    return (
      <div className="panel p-8 text-center">
        <p className="text-sm text-ink-secondary">You don't have permission to view reports.</p>
      </div>
    );
  }

  const report = await getReport(params.reportId);
  if (!report) notFound();

  const [reporter, target] = await Promise.all([
    getUserSummary(report.reporterId),
    getUserSummary(report.targetUserId),
  ]);

  const canReview = hasPermission(identity, 'reports.review');

  return (
    <div className="space-y-4">
      <Breadcrumbs items={[{ label: 'Moderation' }, { label: 'Reports', href: '/moderation/reports' }, { label: report.reportId }]} />

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <div className="panel p-5">
            <div className="mb-3 flex items-center justify-between">
              <h1 className="font-display text-lg font-semibold text-ink-primary">
                {reportReasonLabel(report.reason)}
              </h1>
              <Badge tone={report.status === 'pending' ? 'warning' : report.status === 'reviewed' ? 'success' : 'neutral'} className="capitalize">
                {report.status}
              </Badge>
            </div>
            <p className="text-sm text-ink-primary">{report.details || 'No additional details were provided.'}</p>
            <p className="mt-3 text-xs text-ink-muted">Filed {formatRelativeTime(report.createdAtMs)}</p>
          </div>

          {report.status !== 'pending' && (
            <div className="panel p-5">
              <h2 className="mb-2 font-display text-sm font-semibold text-ink-primary">Review History</h2>
              <p className="text-sm text-ink-secondary">Reviewed by {report.reviewedBy}</p>
              <p className="text-sm text-ink-secondary">{formatRelativeTime(report.reviewedAtMs)}</p>
            </div>
          )}
        </div>

        <div className="space-y-4">
          <div className="panel p-5">
            <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Target User</h2>
            {target ? (
              <Link href={`/users/${target.userId}`} className="text-sm text-brand hover:underline">
                {target.displayName}
              </Link>
            ) : (
              <p className="text-sm text-ink-secondary">{report.targetUserId} (profile not found)</p>
            )}
          </div>

          <div className="panel p-5">
            <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Filed By</h2>
            {reporter ? (
              <Link href={`/users/${reporter.userId}`} className="text-sm text-brand hover:underline">
                {reporter.displayName}
              </Link>
            ) : (
              <p className="text-sm text-ink-secondary">{report.reporterId} (profile not found)</p>
            )}
          </div>

          {report.status === 'pending' && canReview && (
            <div className="panel space-y-2 p-5">
              <h2 className="mb-1 font-display text-sm font-semibold text-ink-primary">Decision</h2>
              <ReportReviewActions reportId={report.reportId} />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
