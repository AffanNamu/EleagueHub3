'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useDiscussionModerationAction() {
  const router = useRouter();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function removeThread(threadId: string) {
    if (!confirm('Remove this discussion thread? Its replies stay in the database but the thread will no longer be visible.')) return;
    setPendingId(threadId);
    setError(null);

    const response = await fetch(`/api/admin/content/discussions/${threadId}`, { method: 'DELETE' });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      setError(body.error ?? 'Something went wrong.');
      setPendingId(null);
      return;
    }
    router.refresh();
    setPendingId(null);
  }

  async function removeReply(threadId: string, replyId: string) {
    if (!confirm('Remove this reply?')) return;
    setPendingId(replyId);
    setError(null);

    const response = await fetch(`/api/admin/content/discussions/${threadId}/replies/${replyId}`, { method: 'DELETE' });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      setError(body.error ?? 'Something went wrong.');
      setPendingId(null);
      return;
    }
    router.refresh();
    setPendingId(null);
  }

  return { removeThread, removeReply, pendingId, error };
}
