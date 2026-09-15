'use client';

import { useState } from 'react';
import Link from 'next/link';
import { FileWarning, CheckCircle2, XCircle } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { useBulkReportReview } from '@/hooks/useBulkReportReview';
import { reportReasonLabel } from '@/types/report';
import { formatRelativeTime } from '@/lib/utils';
import type { ReportStatus, UserReport } from '@/types/report';

const STATUS_TONE: Record<ReportStatus, 'warning' | 'success' | 'neutral'> = {
  pending: 'warning',
  reviewed: 'success',
  dismissed: 'neutral',
};

export function ReportsTable({ reports, canReview }: { reports: UserReport[]; canReview: boolean }) {
  const { submit, submitting, error } = useBulkReportReview();
  const [selected, setSelected] = useState<Set<string>>(new Set());

  if (reports.length === 0) {
    return <EmptyState icon={FileWarning} title="No reports in this view" />;
  }

  const pendingIds = reports.filter((r) => r.status === 'pending').map((r) => r.reportId);
  const allPendingSelected = pendingIds.length > 0 && pendingIds.every((id) => selected.has(id));

  function toggleAll() {
    setSelected(allPendingSelected ? new Set() : new Set(pendingIds));
  }

  function toggleOne(reportId: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(reportId)) next.delete(reportId);
      else next.add(reportId);
      return next;
    });
  }

  async function handleBulk(decision: 'reviewed' | 'dismissed') {
    const ids = Array.from(selected);
    if (ids.length === 0) return;
    if (!confirm(`${decision === 'reviewed' ? 'Mark' : 'Dismiss'} ${ids.length} selected report(s) as ${decision}?`)) {
      return;
    }
    const ok = await submit(ids, decision);
    if (ok) setSelected(new Set());
  }

  return (
    <div className="space-y-3">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      {canReview && selected.size > 0 && (
        <div className="flex items-center justify-between rounded-sm border border-brand/30 bg-brand-faint px-3 py-2">
          <p className="text-sm text-ink-primary">{selected.size} selected</p>
          <div className="flex items-center gap-2">
            <button
              onClick={() => handleBulk('reviewed')}
              disabled={submitting}
              className="flex items-center gap-1.5 rounded-sm bg-signal-success px-3 py-1.5 text-xs font-medium text-base disabled:opacity-60"
            >
              <CheckCircle2 size={13} /> Mark Reviewed
            </button>
            <button
              onClick={() => handleBulk('dismissed')}
              disabled={submitting}
              className="flex items-center gap-1.5 rounded-sm border border-base-border bg-base-raised px-3 py-1.5 text-xs font-medium text-ink-primary hover:border-ink-muted disabled:opacity-60"
            >
              <XCircle size={13} /> Dismiss
            </button>
          </div>
        </div>
      )}

      <div className="panel overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-base-border text-left text-xs text-ink-muted">
              {canReview && (
                <th className="w-10 px-4 py-3">
                  {pendingIds.length > 0 && (
                    <input
                      type="checkbox"
                      checked={allPendingSelected}
                      onChange={toggleAll}
                      className="h-4 w-4 rounded-sm border-base-border accent-brand"
                      aria-label="Select all pending reports"
                    />
                  )}
                </th>
              )}
              <th className="px-4 py-3 font-medium">Report</th>
              <th className="px-4 py-3 font-medium">Reason</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Filed</th>
            </tr>
          </thead>
          <tbody>
            {reports.map((report) => (
              <tr key={report.reportId} className="border-b border-base-border last:border-0 hover:bg-base-raised">
                {canReview && (
                  <td className="px-4 py-3">
                    {report.status === 'pending' && (
                      <input
                        type="checkbox"
                        checked={selected.has(report.reportId)}
                        onChange={() => toggleOne(report.reportId)}
                        className="h-4 w-4 rounded-sm border-base-border accent-brand"
                        aria-label={`Select report ${report.reportId}`}
                      />
                    )}
                  </td>
                )}
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
    </div>
  );
}
