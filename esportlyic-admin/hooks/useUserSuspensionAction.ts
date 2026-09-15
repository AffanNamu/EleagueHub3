'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useUserSuspensionAction(userId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(suspended: boolean, reason: string): Promise<boolean> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/users/${userId}/suspension`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ suspended, reason }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? 'Something went wrong.');
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

  return { submit, submitting, error };
}
