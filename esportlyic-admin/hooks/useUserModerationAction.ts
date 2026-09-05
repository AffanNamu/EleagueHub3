'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useUserModerationAction(userId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(body: { muted?: boolean; banned?: boolean; isGlobalChatAdmin?: boolean }) {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/users/${userId}/moderation`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        const responseBody = await response.json().catch(() => ({}));
        setError(responseBody.error ?? 'Something went wrong.');
        setSubmitting(false);
        return;
      }

      router.refresh();
      setSubmitting(false);
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
    }
  }

  return { submit, submitting, error };
}
