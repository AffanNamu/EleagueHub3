'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  return response.json().catch(() => ({}));
}

export function useTeamRename(leagueId: string) {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function rename(teamId: string, name: string): Promise<boolean> {
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch(`/api/admin/leagues/${leagueId}/teams/${teamId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name }),
      });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        return false;
      }
      router.refresh();
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      return false;
    } finally {
      setSubmitting(false);
    }
  }

  return { rename, submitting, error };
}

export function useTeamDelete(leagueId: string) {
  const router = useRouter();
  const [deleting, setDeleting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function remove(teamId: string, name: string): Promise<boolean> {
    if (
      !confirm(
        `Delete "${name}"? Roster members will be released back to Unassigned. Any existing matches that reference this team will still point at it and may display incorrectly. This cannot be undone.`,
      )
    ) {
      return false;
    }

    setDeleting(teamId);
    setError(null);
    try {
      const response = await fetch(`/api/admin/leagues/${leagueId}/teams/${teamId}`, { method: 'DELETE' });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        return false;
      }
      router.refresh();
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      return false;
    } finally {
      setDeleting(null);
    }
  }

  return { remove, deleting, error };
}

export function useRemoveTeamMember(leagueId: string) {
  const router = useRouter();
  const [removing, setRemoving] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function remove(membershipId: string, displayName: string): Promise<boolean> {
    if (!confirm(`Remove ${displayName} from this team's roster?`)) {
      return false;
    }

    setRemoving(membershipId);
    setError(null);
    try {
      const response = await fetch(`/api/admin/leagues/${leagueId}/memberships/${membershipId}`, {
        method: 'DELETE',
      });
      const body = await parseJson(response);
      if (!response.ok) {
        setError((body.error as string) ?? 'Something went wrong.');
        return false;
      }
      router.refresh();
      return true;
    } catch {
      setError('Network error. Please check your connection and try again.');
      return false;
    } finally {
      setRemoving(null);
    }
  }

  return { remove, removing, error };
}
