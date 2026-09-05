// lib/repositories/analyticsAdminRepository.ts
//
// Server-only breakdown queries. Every number is a real per-value count
// against confirmed fields — no scheduled aggregation collection exists
// yet (revenue_by_day / analytics_summary in firestore.rules have no
// writer), so this reads live rather than from a precomputed rollup.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { leagueFormatFromIndex, leagueFormatLabel } from '@/types/league';

export interface BreakdownRow {
  label: string;
  count: number;
}

async function countWhere(path: string, field: string, value: unknown): Promise<number> {
  const snap = await adminDb.collection(path).where(field, '==', value).count().get();
  return snap.data().count;
}

export async function getPlanBreakdown(): Promise<BreakdownRow[]> {
  const [basic, pro, elite, totalUsers] = await Promise.all([
    countWhere('users', 'activePlanId', 'basic'),
    countWhere('users', 'activePlanId', 'pro'),
    countWhere('users', 'activePlanId', 'elite'),
    adminDb.collection('users').count().get().then((s) => s.data().count),
  ]);

  const unset = Math.max(0, totalUsers - basic - pro - elite);

  return [
    { label: 'Basic', count: basic },
    { label: 'Pro', count: pro },
    { label: 'Elite', count: elite },
    { label: 'No plan set', count: unset },
  ];
}

export async function getOrganizerVerificationBreakdown(): Promise<BreakdownRow[]> {
  const [pending, approved, rejected, infoRequested, totalOrganizers] = await Promise.all([
    countWhere('master_leagues', 'verificationStatus', 'pending'),
    countWhere('master_leagues', 'verificationStatus', 'approved'),
    countWhere('master_leagues', 'verificationStatus', 'rejected'),
    countWhere('master_leagues', 'verificationStatus', 'info_requested'),
    adminDb.collection('master_leagues').count().get().then((s) => s.data().count),
  ]);

  const notStarted = Math.max(0, totalOrganizers - pending - approved - rejected - infoRequested);

  return [
    { label: 'Approved', count: approved },
    { label: 'Pending', count: pending },
    { label: 'Info Requested', count: infoRequested },
    { label: 'Rejected', count: rejected },
    { label: 'Never Applied', count: notStarted },
  ];
}

export async function getLeagueFormatBreakdown(): Promise<BreakdownRow[]> {
  const counts = await Promise.all(
    [0, 1, 2, 3].map((index) => countWhere('leagues', 'format', index)),
  );

  return counts.map((count, index) => ({
    label: leagueFormatLabel(leagueFormatFromIndex(index)),
    count,
  }));
}
