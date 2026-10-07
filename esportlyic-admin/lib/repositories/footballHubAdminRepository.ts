// lib/repositories/footballHubAdminRepository.ts
//
// Server-only reads/writes for the Football Hub admin panel. Mirrors the
// Worker's own Firestore shapes exactly (worker/src/index.js):
//   football_metrics/{YYYY-MM-DD}  -- apiRequests/cacheHits/providerErrors,
//     written by _recordFootballMetric on every proxied request and by
//     the live-score poller.
//   football_config/settings       -- { pollerEnabled, apiFootballKey }
//     checked by the poller's `scheduled` handler and by
//     API_FOOTBALL_PROVIDER.buildHeaders before every upstream call.
//     pollerEnabled: missing doc/field means "enabled" (the poller's
//     current default behavior). apiFootballKey: the Worker's
//     _getApiFootballKey reads this first and falls back to its own
//     API_FOOTBALL_KEY secret when it's empty, so setting it here lets the
//     key be rotated without a Worker redeploy.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';

export interface FootballHubMetrics {
  date: string;
  apiRequests: number;
  cacheHits: number;
  providerErrors: number;
  /** Subset of providerErrors specifically identified as the free daily quota being exhausted. */
  rateLimitHits: number;
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
    rateLimitHits: typeof data.rateLimitHits === 'number' ? data.rateLimitHits : 0,
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

export interface FootballHubApiKeyStatus {
  /** true once any key has been set here (not the GitHub-secret fallback). */
  configured: boolean;
  /** Last 4 characters only -- the full value is never read back to the browser. */
  maskedKey: string | null;
  keyUpdatedAtMs: number | null;
  keyUpdatedByEmail: string | null;
}

function maskKey(key: string): string {
  const tail = key.slice(-4);
  return `${'•'.repeat(Math.max(key.length - 4, 4))}${tail}`;
}

export async function getFootballHubApiKeyStatus(): Promise<FootballHubApiKeyStatus> {
  const snap = await adminDb.collection('football_config').doc('settings').get();
  const data = snap.data() ?? {};
  const key = typeof data.apiFootballKey === 'string' ? data.apiFootballKey.trim() : '';

  return {
    configured: key.length > 0,
    maskedKey: key ? maskKey(key) : null,
    keyUpdatedAtMs: typeof data.apiFootballKeyUpdatedAtMs === 'number' ? data.apiFootballKeyUpdatedAtMs : null,
    keyUpdatedByEmail: typeof data.apiFootballKeyUpdatedByEmail === 'string' ? data.apiFootballKeyUpdatedByEmail : null,
  };
}

export async function setFootballHubApiKey(
  key: string,
  actor: { uid: string; email: string | null },
): Promise<FootballHubApiKeyStatus> {
  const trimmed = key.trim();
  const payload = {
    apiFootballKey: trimmed,
    apiFootballKeyUpdatedAtMs: Date.now(),
    apiFootballKeyUpdatedByUid: actor.uid,
    apiFootballKeyUpdatedByEmail: actor.email,
  };
  await adminDb.collection('football_config').doc('settings').set(payload, { merge: true });

  return {
    configured: trimmed.length > 0,
    maskedKey: trimmed ? maskKey(trimmed) : null,
    keyUpdatedAtMs: payload.apiFootballKeyUpdatedAtMs,
    keyUpdatedByEmail: actor.email,
  };
}
