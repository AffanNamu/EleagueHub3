'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useReportReviewAction(reportId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(decision: 'reviewed' | 'dismissed'): Promise<boolean> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/reports/${reportId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ decision }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? 'Something went wrong. Please try again.');
        setSubmitting(false);
        return false;
      }

      router.push('/moderation/reports');
      router.refresh();
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
      return false;
    }
  }

  return { submit, submitting, error };
}
