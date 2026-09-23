'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { AppUpdateConfigEdit } from '@/types/appUpdateConfig';

export function useAppUpdateConfigSave() {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function save(edit: AppUpdateConfigEdit): Promise<boolean> {
    setSubmitting(true);
    setError(null);
    setSaved(false);

    try {
      const response = await fetch('/api/admin/settings/app-update', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ edit }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.error ?? 'Something went wrong.');
        setSubmitting(false);
        return false;
      }

      setSaved(true);
      setSubmitting(false);
      router.refresh();
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
      return false;
    }
  }

  return { save, submitting, error, saved };
}
