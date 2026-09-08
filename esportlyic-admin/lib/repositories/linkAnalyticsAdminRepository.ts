// lib/repositories/linkAnalyticsAdminRepository.ts
//
// Server-only reads of analytics_link_events / analytics_link_rollups.
//
// ENTITY NAME RESOLUTION — SCOPED HONESTLY:
// entityId alone isn't human-readable, so resolveEntityName() looks up a
// real display name for the four entity types whose backing collection
// is confirmed elsewhere in this codebase: userProfile -> users,
// organizerWorkspace -> master_leagues, post -> public_posts,
// marketProduct -> marketplace_products. The remaining five types
// (competition, team, tournament, news, achievement) have NO confirmed
// collection mapping — 'competition' and 'tournament' being distinct
// entity types when only one `leagues` collection has ever been
// confirmed is a real ambiguity, not resolved here. Those fall back to
// a plain "entityType · entityId" label rather than guessing a
// collection that could silently show the wrong content.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import type { ChannelBreakdownRow, LinkEntityType, LinkRollup } from '@/types/linkAnalytics';

const RESOLVABLE_COLLECTIONS: Partial<Record<LinkEntityType, { collection: string; nameField: string }>> = {
  userProfile: { collection: 'users', nameField: 'teamName' },
  organizerWorkspace: { collection: 'master_leagues', nameField: 'name' },
  post: { collection: 'public_posts', nameField: 'text' },
  marketProduct: { collection: 'marketplace_products', nameField: 'name' },
};

async function resolveEntityName(entityType: LinkEntityType, entityId: string): Promise<string | null> {
  const mapping = RESOLVABLE_COLLECTIONS[entityType];
  if (!mapping) return null;

  try {
    const snap = await adminDb.collection(mapping.collection).doc(entityId).get();
    if (!snap.exists) return null;
    const value = snap.data()?.[mapping.nameField];
    if (typeof value !== 'string' || !value.trim()) return null;
    return value.trim().length > 60 ? `${value.trim().slice(0, 57)}...` : value.trim();
  } catch {
    return null;
  }
}

export async function getTopRollups(params: {
  sortBy: 'shareCount' | 'clickCount';
  limit?: number;
}): Promise<LinkRollup[]> {
  const { sortBy, limit = 10 } = params;

  const snap = await adminDb
    .collection('analytics_link_rollups')
    .orderBy(sortBy, 'desc')
    .limit(limit)
    .get();

  const rollups = await Promise.all(
    snap.docs.map(async (doc) => {
      const data = doc.data();
      const entityType = (data.entityType as LinkEntityType) ?? 'post';
      const entityId = (data.entityId as string) ?? '';
      const entityName = await resolveEntityName(entityType, entityId);

      return {
        rollupId: doc.id,
        entityType,
        entityId,
        entityName,
        shareCount: typeof data.shareCount === 'number' ? data.shareCount : 0,
        clickCount: typeof data.clickCount === 'number' ? data.clickCount : 0,
        lastEventAtMs: typeof data.lastEventAtMs === 'number' ? data.lastEventAtMs : 0,
      };
    }),
  );

  return rollups;
}

/**
 * Channel breakdown reads the raw event log in memory (rollups don't
 * track channel), capped at the 3000 most recent events — sufficient
 * for a "where does sharing come from" snapshot at current scale;
 * should graduate to a scheduled per-channel rollup if event volume
 * grows enough that this cap starts hiding older channel activity.
 */
export async function getChannelBreakdown(): Promise<ChannelBreakdownRow[]> {
  const EVENT_SAMPLE_LIMIT = 3000;

  const snap = await adminDb
    .collection('analytics_link_events')
    .orderBy('createdAtMs', 'desc')
    .limit(EVENT_SAMPLE_LIMIT)
    .get();

  const counts = new Map<string, { shares: number; clicks: number }>();

  for (const doc of snap.docs) {
    const data = doc.data();
    const channel = (data.channel as string) ?? 'unknown';
    const eventType = data.eventType as string;
    const existing = counts.get(channel) ?? { shares: 0, clicks: 0 };
    if (eventType === 'share') existing.shares += 1;
    else if (eventType === 'click') existing.clicks += 1;
    counts.set(channel, existing);
  }

  return Array.from(counts.entries())
    .map(([channel, { shares, clicks }]) => ({ channel, shares, clicks }))
    .sort((a, b) => b.shares + b.clicks - (a.shares + a.clicks));
}
