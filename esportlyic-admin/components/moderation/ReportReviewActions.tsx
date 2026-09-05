'use client';

import { CheckCircle2, XCircle } from 'lucide-react';
import { useReportReviewAction } from '@/hooks/useReportReviewAction';

export function ReportReviewActions({ reportId }: { reportId: string }) {
  const { submit, submitting, error } = useReportReviewAction(reportId);

  return (
    <div className="space-y-2">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}
      <button
        onClick={() => submit('reviewed')}
        disabled={submitting}
        className="flex w-full items-center justify-center gap-2 rounded-sm bg-signal-success py-2 text-sm font-medium text-base disabled:opacity-60"
      >
        <CheckCircle2 size={16} /> Mark Reviewed
      </button>
      <button
        onClick={() => submit('dismissed')}
        disabled={submitting}
        className="flex w-full items-center justify-center gap-2 rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-ink-muted disabled:opacity-60"
      >
        <XCircle size={16} /> Dismiss
      </button>
    </div>
  );
}
