// lib/repositories/footballNewsAdminRepository.ts
//
// Server-only reads/writes for the Football News admin panel. Mirrors
// footballHubAdminRepository.ts's shape exactly, but for a separate
// provider/quota (GNews, not API-Football) and the Worker's own separate
// Firestore docs for it (worker/src/index.js):
//   football_news_metrics/{YYYY-MM-DD} -- apiRequests/cacheHits/
//     providerErrors, written by _recordFootballNewsMetric on every
//     /football/news request. Deliberately NOT mixed into football_metrics
//     -- unrelated providers, unrelated quotas.
//   football_news_config/settings      -- { gnewsApiKey }. The Worker's
//     _getGNewsApiKey reads this first and falls back to its own
//     GNEWS_API_KEY secret when it's empty, so setting it here lets the
//     key be rotated without a Worker redeploy. No poller toggle here --
//     there's no live background poller for news, unlike Football Hub's
//     live-score poller.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';

export interface FootballNewsMetrics {
  date: string;
  apiRequests: number;
  cacheHits: number;
  providerErrors: number;
  lastUpdatedMs: number | null;
}

function todayUtc(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function getFootballNewsMetrics(date?: string): Promise<FootballNewsMetrics> {
  const d = date ?? todayUtc();
  const snap = await adminDb.collection('football_news_metrics').doc(d).get();
  const data = snap.data() ?? {};

  return {
    date: d,
    apiRequests: typeof data.apiRequests === 'number' ? data.apiRequests : 0,
    cacheHits: typeof data.cacheHits === 'number' ? data.cacheHits : 0,
    providerErrors: typeof data.providerErrors === 'number' ? data.providerErrors : 0,
    lastUpdatedMs: typeof data.lastUpdatedMs === 'number' ? data.lastUpdatedMs : null,
  };
}

export interface FootballNewsApiKeyStatus {
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

export async function getFootballNewsApiKeyStatus(): Promise<FootballNewsApiKeyStatus> {
  const snap = await adminDb.collection('football_news_config').doc('settings').get();
  const data = snap.data() ?? {};
  const key = typeof data.gnewsApiKey === 'string' ? data.gnewsApiKey.trim() : '';

  return {
    configured: key.length > 0,
    maskedKey: key ? maskKey(key) : null,
    keyUpdatedAtMs: typeof data.gnewsApiKeyUpdatedAtMs === 'number' ? data.gnewsApiKeyUpdatedAtMs : null,
    keyUpdatedByEmail: typeof data.gnewsApiKeyUpdatedByEmail === 'string' ? data.gnewsApiKeyUpdatedByEmail : null,
  };
}

export async function setFootballNewsApiKey(
  key: string,
  actor: { uid: string; email: string | null },
): Promise<FootballNewsApiKeyStatus> {
  const trimmed = key.trim();
  const payload = {
    gnewsApiKey: trimmed,
    gnewsApiKeyUpdatedAtMs: Date.now(),
    gnewsApiKeyUpdatedByUid: actor.uid,
    gnewsApiKeyUpdatedByEmail: actor.email,
  };
  await adminDb.collection('football_news_config').doc('settings').set(payload, { merge: true });

  return {
    configured: trimmed.length > 0,
    maskedKey: trimmed ? maskKey(trimmed) : null,
    keyUpdatedAtMs: payload.gnewsApiKeyUpdatedAtMs,
    keyUpdatedByEmail: actor.email,
  };
}
