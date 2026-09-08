// lib/repositories/analyticsAdminRepository.ts

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

export interface CountryBreakdown {
  rows: BreakdownRow[];
  recordedCount: number;
  totalUserCount: number;
  sampleCapped: boolean;
}

/**
 * Users by country — sourced from user_search/{uid}.country, the ONLY
 * place country is recorded anywhere in this codebase (confirmed
 * against user_search_repository.dart + country_resolver_service.dart).
 *
 * TWO REAL ACCURACY LIMITATIONS, surfaced in the UI, not hidden here:
 *
 * 1. Coverage gap: user_search/{uid} is only created/backfilled
 *    opportunistically (backfillCountryIfMissing() — runs best-effort,
 *    can fail silently, and simply never runs for some sessions). Not
 *    every user in `users` has a matching user_search doc with a
 *    country value.
 *
 * 2. Nigeria-bias: CountryResolverService was built for CURRENCY
 *    selection, not demographics — its fallback chain ends in a
 *    hardcoded "NG" whenever locale/IP resolution fails for ANY reason.
 *    That means the "NG" bucket below is inflated by an unknown number
 *    of resolution failures, not necessarily real Nigerian users. This
 *    is a structural bias in the source data, not a bug in this query.
 *
 * Reads up to 2000 user_search docs (ordered by most recently updated)
 * and aggregates in memory — fine at current scale, should graduate to
 * a scheduled aggregation write if the platform grows meaningfully
 * beyond that.
 */
export async function getUserCountryBreakdown(): Promise<CountryBreakdown> {
  const SAMPLE_LIMIT = 2000;

  const [searchSnap, totalUserCount] = await Promise.all([
    adminDb.collection('user_search').orderBy('updatedAtMs', 'desc').limit(SAMPLE_LIMIT).get(),
    adminDb.collection('users').count().get().then((s) => s.data().count),
  ]);

  const counts = new Map<string, number>();
  let recordedCount = 0;

  for (const doc of searchSnap.docs) {
    const country = (doc.data().country as string) ?? '';
    if (!country.trim()) continue;
    recordedCount += 1;
    counts.set(country, (counts.get(country) ?? 0) + 1);
  }

  const rows = Array.from(counts.entries())
    .sort((a, b) => b[1] - a[1])
    .map(([label, count]) => ({ label, count }));

  return {
    rows,
    recordedCount,
    totalUserCount,
    sampleCapped: searchSnap.docs.length >= SAMPLE_LIMIT,
  };
}
