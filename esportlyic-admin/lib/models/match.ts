// lib/models/match.ts
//
// MatchStatus values confirmed directly against enums.dart. 'completed'
// is documented there as a "backward-compatible alias" for 'played' —
// both are treated as finished states.

import type { MatchStatus } from '@/types/match';

const CONFIRMED_STATUSES: MatchStatus[] = ['scheduled', 'pendingProof', 'underReview', 'played', 'completed'];

export function isConfirmedStatus(status: string): status is 'scheduled' | 'pendingProof' | 'underReview' | 'played' | 'completed' {
  return CONFIRMED_STATUSES.includes(status);
}

export function matchStatusLabel(status: string): string {
  switch (status) {
    case 'scheduled':
      return 'Scheduled';
    case 'pendingProof':
      return 'Pending Proof';
    case 'underReview':
      return 'Under Review';
    case 'played':
      return 'Played';
    case 'completed':
      return 'Completed';
    default:
      return status || 'Unknown';
  }
}

export function matchStatusTone(status: string): 'neutral' | 'success' | 'warning' | 'info' {
  if (status === 'played' || status === 'completed') return 'success';
  if (status === 'scheduled') return 'neutral';
  if (status === 'pendingProof' || status === 'underReview') return 'warning';
  return 'info';
}

export function isFixtureFinished(match: { status: string; homeScore: number | null; awayScore: number | null }): boolean {
  return (match.status === 'played' || match.status === 'completed') && match.homeScore !== null && match.awayScore !== null;
}
