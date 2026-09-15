'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useLeagueCouponsToggle(leagueId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function setEnabled(enabled: boolean): Promise<boolean> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/leagues/${leagueId}/coupons`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ enabled }),
      });
      const body = await parseJson(response);

      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        setSubmitting(false);
        return false;
      }

      router.refresh();
      setSubmitting(false);
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
      return false;
    }
  }

  return { setEnabled, submitting, error };
}
