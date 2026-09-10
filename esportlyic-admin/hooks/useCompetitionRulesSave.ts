'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { CompetitionRules } from '@/types/competitionRules';

export function useCompetitionRulesSave(leagueId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(updates: Partial<CompetitionRules>): Promise<boolean> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(`/api/admin/leagues/${leagueId}/rules`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ updates }),
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

  return { save, submitting, error };
}
