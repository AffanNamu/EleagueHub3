// lib/models/match.ts

import type { MatchStatus } from '@/types/match';

const CONFIRMED_STATUSES: MatchStatus[] = ['scheduled', 'completed', 'played'];

export function isConfirmedStatus(status: string): status is 'scheduled' | 'completed' | 'played' {
  return CONFIRMED_STATUSES.includes(status);
}

export function matchStatusLabel(status: string): string {
  switch (status) {
    case 'scheduled':
      return 'Scheduled';
    case 'completed':
      return 'Completed';
    case 'played':
      return 'Played';
    default:
      return status || 'Unknown';
  }
}

export function matchStatusTone(status: string): 'neutral' | 'success' | 'warning' {
  if (status === 'completed' || status === 'played') return 'success';
  if (status === 'scheduled') return 'neutral';
  return 'warning';
}

export function isFixtureFinished(match: { status: string; homeScore: number | null; awayScore: number | null }): boolean {
  return (match.status === 'completed' || match.status === 'played') && match.homeScore !== null && match.awayScore !== null;
}
