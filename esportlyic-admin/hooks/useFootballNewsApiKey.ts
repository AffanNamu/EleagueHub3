'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useFootballNewsApiKey() {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function setApiKey(key: string) {
    setPending(true);
    setError(null);
    try {
      const response = await fetch('/api/admin/football-news', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ gnewsApiKey: key }),
      });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        return false;
      }
      router.refresh();
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      return false;
    } finally {
      setPending(false);
    }
  }

  return { setApiKey, pending, error };
}
