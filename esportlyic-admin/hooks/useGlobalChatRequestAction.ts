'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useGlobalChatRequestAction() {
  const router = useRouter();
  const [pendingUid, setPendingUid] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function submit(uid: string, decision: 'approved' | 'rejected') {
    setPendingUid(uid);
    setError(null);

    try {
      const response = await fetch(`/api/admin/global-chat-requests/${uid}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ decision }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? 'Something went wrong.');
        setPendingUid(null);
        return;
      }

      router.refresh();
      setPendingUid(null);
    } catch {
      setError('Network error. Please check your connection and try again.');
      setPendingUid(null);
    }
  }

  return { submit, pendingUid, error };
}
