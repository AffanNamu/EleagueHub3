'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { League, LeagueInput } from '@/types/league';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useLeagueSave(leagueId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(input: LeagueInput): Promise<League | null> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/leagues/${leagueId}`, {
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

      router.push(`/leagues/${leagueId}`);
      router.refresh();
      return (body.league as League) ?? null;
    } catch {
      setError('Network error. Please check your connection and try again.');
      setSubmitting(false);
      return null;
    }
  }

  return { save, submitting, error };
}

export function useLeagueDelete() {
  const router = useRouter();
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove(leagueId: string, name: string) {
    if (
      !confirm(
        `Delete "${name}"? This permanently deletes the league AND all its matches, teams, and standings. This cannot be undone.`,
      )
    ) {
      return false;
    }

    setDeleting(true);
    setError(null);
    try {
      const response = await fetch(`/api/admin/leagues/${leagueId}`, { method: 'DELETE' });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        return false;
      }
      router.push('/leagues');
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
