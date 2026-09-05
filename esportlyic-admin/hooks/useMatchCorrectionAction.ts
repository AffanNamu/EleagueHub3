'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function useMatchCorrectionAction(leagueId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function correctFixture(
    matchId: string,
    body: { homeScore: number; awayScore: number; status: string },
  ): Promise<boolean> {
    return submit(`/api/admin/leagues/${leagueId}/matches/${matchId}`, body);
  }

  async function correctKnockout(
    matchId: string,
    body: { homeScore: number; awayScore: number; status: string; tiebreakWinnerTeamId: string | null },
  ): Promise<boolean> {
    return submit(`/api/admin/leagues/${leagueId}/knockout/${matchId}`, body);
  }

  async function submit(url: string, body: Record<string, unknown>): Promise<boolean> {
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch(url, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        const responseBody = await response.json().catch(() => ({}));
        setError(responseBody.error ?? 'Something went wrong.');
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

  return { correctFixture, correctKnockout, submitting, error };
}
