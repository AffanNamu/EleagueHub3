// lib/repositories/footballHubAdminRepository.ts
//
// Server-only reads/writes for the Football Hub admin panel. Mirrors the
// Worker's own Firestore shapes exactly (worker/src/index.js):
//   football_metrics/{YYYY-MM-DD}  -- apiRequests/cacheHits/providerErrors,
//     written by _recordFootballMetric on every proxied request and by
//     the live-score poller.
//   football_config/settings       -- { pollerEnabled } checked by the
//     poller's `scheduled` handler before it runs; missing doc or missing
//     field both mean "enabled" (the poller's current default behavior).

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';

export interface FootballHubMetrics {
  date: string;
  apiRequests: number;
  cacheHits: number;
  providerErrors: number;
  lastUpdatedMs: number | null;
}

export interface FootballHubConfig {
  pollerEnabled: boolean;
  updatedAtMs: number | null;
  updatedByEmail: string | null;
}

function todayUtc(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function getFootballHubMetrics(date?: string): Promise<FootballHubMetrics> {
  const d = date ?? todayUtc();
  const snap = await adminDb.collection('football_metrics').doc(d).get();
  const data = snap.data() ?? {};

  return {
    date: d,
    apiRequests: typeof data.apiRequests === 'number' ? data.apiRequests : 0,
    cacheHits: typeof data.cacheHits === 'number' ? data.cacheHits : 0,
    providerErrors: typeof data.providerErrors === 'number' ? data.providerErrors : 0,
    lastUpdatedMs: typeof data.lastUpdatedMs === 'number' ? data.lastUpdatedMs : null,
  };
}

export async function getFootballHubConfig(): Promise<FootballHubConfig> {
  const snap = await adminDb.collection('football_config').doc('settings').get();
  const data = snap.data() ?? {};

  return {
    // Doc/field absent => poller runs (matches the Worker's own default).
    pollerEnabled: data.pollerEnabled !== false,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : null,
    updatedByEmail: typeof data.updatedByEmail === 'string' ? data.updatedByEmail : null,
  };
}

export async function setFootballHubPollerEnabled(
  enabled: boolean,
  actor: { uid: string; email: string | null },
): Promise<FootballHubConfig> {
  const payload = {
    pollerEnabled: enabled,
    updatedAtMs: Date.now(),
    updatedByUid: actor.uid,
    updatedByEmail: actor.email,
  };
  await adminDb.collection('football_config').doc('settings').set(payload, { merge: true });

  return {
    pollerEnabled: enabled,
    updatedAtMs: payload.updatedAtMs,
    updatedByEmail: actor.email,
  };
}
