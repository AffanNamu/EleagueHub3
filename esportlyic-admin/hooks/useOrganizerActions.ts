'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Organizer, OrganizerInput } from '@/types/organizer';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useOrganizerSave(organizerId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(input: OrganizerInput): Promise<Organizer | null> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/organizers/${organizerId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(input),
      });
      const body = await parseJson(response);

      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        setSubmitting(false);
        return null;
      }

      router.push(`/organizers/${organizerId}`);
      router.refresh();
      return (body.organizer as Organizer) ?? null;
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
      return null;
    }
  }

  return { save, submitting, error };
}

export function useOrganizerDelete() {
  const router = useRouter();
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove(organizerId: string, name: string) {
    if (
      !confirm(
        `Delete "${name}"? This permanently deletes the organizer workspace AND all its leagues data, staff, and audit history tied to this workspace. This cannot be undone.`,
      )
    ) {
      return false;
    }

    setDeleting(true);
    setError(null);
    try {
      const response = await fetch(`/api/admin/organizers/${organizerId}`, { method: 'DELETE' });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        return false;
      }
      router.push('/organizers');
      router.refresh();
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      return false;
    } finally {
      setDeleting(false);
    }
  }

  return { remove, deleting, error };
}
