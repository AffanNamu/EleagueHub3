'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useFootballHubPollerToggle() {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function setPollerEnabled(enabled: boolean) {
    setPending(true);
    setError(null);
    try {
      const response = await fetch('/api/admin/football-hub', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pollerEnabled: enabled }),
      });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
      } else {
        router.refresh();
      }
    } catch {
      setError('Network error. Please check your connection and try again.');
    } finally {
      setPending(false);
    }
  }

  return { setPollerEnabled, pending, error };
}
