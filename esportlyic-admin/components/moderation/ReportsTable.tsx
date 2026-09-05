import Link from 'next/link';
import { FileWarning } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { reportReasonLabel } from '@/types/report';
import { formatRelativeTime } from '@/lib/utils';
import type { ReportStatus, UserReport } from '@/types/report';

const STATUS_TONE: Record<ReportStatus, 'warning' | 'success' | 'neutral'> = {
  pending: 'warning',
  reviewed: 'success',
  dismissed: 'neutral',
};

export function ReportsTable({ reports }: { reports: UserReport[] }) {
  if (reports.length === 0) {
    return <EmptyState icon={FileWarning} title="No reports in this view" />;
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">Report</th>
            <th className="px-4 py-3 font-medium">Reason</th>
            <th className="px-4 py-3 font-medium">Status</th>
            <th className="px-4 py-3 font-medium">Filed</th>
          </tr>
        </thead>
        <tbody>
          {reports.map((report) => (
            <tr key={report.reportId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
              <td className="px-4 py-3">
                <Link href={`/moderation/reports/${report.reportId}`}>
                  <p className="font-medium text-ink-primary">Against {report.targetUserId}</p>
                  <p className="text-xs text-ink-muted">Filed by {report.reporterId}</p>
                </Link>
              </td>
              <td className="px-4 py-3 text-ink-secondary">{reportReasonLabel(report.reason)}</td>
              <td className="px-4 py-3">
                <Badge tone={STATUS_TONE[report.status]} className="capitalize">
                  {report.status}
                </Badge>
              </td>
              <td className="px-4 py-3 text-ink-secondary">
                {report.createdAtMs ? formatRelativeTime(report.createdAtMs) : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
