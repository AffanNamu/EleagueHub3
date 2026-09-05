'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useContentModerationAction() {
  const router = useRouter();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function removePost(postId: string) {
    if (!confirm('Remove this post? This can be reversed only by a direct database edit.')) return;
    setPendingId(postId);
    setError(null);

    const response = await fetch(`/api/admin/content/posts/${postId}`, { method: 'DELETE' });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      setError(body.error ?? 'Something went wrong.');
      setPendingId(null);
      return;
    }
    router.refresh();
    setPendingId(null);
  }

  async function removeComment(postId: string, commentId: string) {
    if (!confirm('Remove this comment?')) return;
    setPendingId(commentId);
    setError(null);

    const response = await fetch(`/api/admin/content/comments/${postId}/${commentId}`, { method: 'DELETE' });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      setError(body.error ?? 'Something went wrong.');
      setPendingId(null);
      return;
    }
    router.refresh();
    setPendingId(null);
  }

  return { removePost, removeComment, pendingId, error };
}
