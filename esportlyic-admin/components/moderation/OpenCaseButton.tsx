'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { FolderPlus } from 'lucide-react';

export function OpenCaseButton({
  targetUserId,
  targetUserName,
  reportId,
  reason,
}: {
  targetUserId: string;
  targetUserName: string;
  reportId: string;
  reason: string;
}) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleClick() {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch('/api/admin/moderation/cases', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          targetUserId,
          targetUserName,
          reason,
          linkedEvidence: [{ type: 'report', id: reportId, label: `Report: ${reason}` }],
        }),
      });

      const body = await response.json().catch(() => ({}));

      if (!response.ok) {
        setError(body.error ?? 'Something went wrong.');
        setSubmitting(false);
        return;
      }

      router.push(`/moderation/cases/${body.case.caseId}`);
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
    }
  }

  return (
    <div className="space-y-2">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}
      <button
        onClick={handleClick}
        disabled={submitting}
        className="flex w-full items-center justify-center gap-2 rounded-sm border border-base-border bg-base-raised py-2 text-sm font-medium text-ink-primary hover:border-brand disabled:opacity-60"
      >
        <FolderPlus size={15} /> {submitting ? 'Opening…' : 'Open Investigation Case'}
      </button>
    </div>
  );
}
