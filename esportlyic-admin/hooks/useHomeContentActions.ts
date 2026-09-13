'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { HomeContentInput, HomeContentItem } from '@/types/homeContent';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useHomeContentSave(existingId?: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(input: HomeContentInput): Promise<HomeContentItem | null> {
    setSubmitting(true);
    setError(null);

    try {
      const url = existingId ? `/api/admin/content/home/${existingId}` : '/api/admin/content/home';
      const method = existingId ? 'PATCH' : 'POST';
      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(input),
      });
      const body = await parseJson(response);

      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        setSubmitting(false);
        return null;
      }

      router.push('/content/home');
      router.refresh();
      return (body.item as HomeContentItem) ?? null;
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
      return null;
    }
  }

  return { save, submitting, error };
}

export function useHomeContentListActions() {
  const router = useRouter();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function toggleActive(id: string, active: boolean) {
    setPendingId(id);
    setError(null);
    try {
      const response = await fetch(`/api/admin/content/home/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ active }),
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
      setPendingId(null);
    }
  }

  async function remove(id: string) {
    if (!confirm('Delete this content item? This cannot be undone.')) return;
    setPendingId(id);
    setError(null);
    try {
      const response = await fetch(`/api/admin/content/home/${id}`, { method: 'DELETE' });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
      } else {
        router.refresh();
      }
    } catch {
      setError('Network error. Please check your connection and try again.');
    } finally {
      setPendingId(null);
    }
  }

  return { toggleActive, remove, pendingId, error };
}
