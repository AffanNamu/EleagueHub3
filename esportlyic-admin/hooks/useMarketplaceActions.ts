'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { MarketplaceProduct, MarketplaceProductInput } from '@/types/marketplaceProduct';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useMarketplaceProductSave(existingId?: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(input: MarketplaceProductInput): Promise<MarketplaceProduct | null> {
    setSubmitting(true);
    setError(null);

    try {
      const url = existingId ? `/api/admin/marketplace/${existingId}` : '/api/admin/marketplace';
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

      router.push('/marketplace');
      router.refresh();
      return (body.item as MarketplaceProduct) ?? null;
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
      return null;
    }
  }

  return { save, submitting, error };
}

export function useMarketplaceListActions() {
  const router = useRouter();
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function remove(id: string, name: string) {
    if (!confirm(`Delete "${name}"? This cannot be undone.`)) return;
    setPendingId(id);
    setError(null);
    try {
      const response = await fetch(`/api/admin/marketplace/${id}`, { method: 'DELETE' });
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

  return { remove, pendingId, error };
}
