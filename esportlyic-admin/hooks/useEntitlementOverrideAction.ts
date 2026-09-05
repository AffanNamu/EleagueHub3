'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useEntitlementOverrideAction(userId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function grant(plan: string, duration: string, expiresAtMs: number): Promise<boolean> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/users/${userId}/entitlement`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan, duration, expiresAtMs }),
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

  async function revoke(): Promise<boolean> {
    if (!confirm('Revoke this manually-granted entitlement?')) return false;

    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/users/${userId}/entitlement`, { method: 'DELETE' });

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

  return { grant, revoke, submitting, error };
}
