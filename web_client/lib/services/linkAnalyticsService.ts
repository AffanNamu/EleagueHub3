import { doc, collection, setDoc, increment } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

// Mirrors lib/core/analytics/link_analytics_service.dart exactly — same
// two collections, same field shapes — so web-originated clicks/shares
// land in the same analytics_link_events log and
// analytics_link_rollups/{entityType}_{entityId} rollup counters mobile
// writes to. Deliberately best-effort: a failed analytics write must
// never block the page it's attached to, so every export here swallows
// its own errors.

export type LinkEntityType =
  | 'userProfile' | 'competition' | 'team' | 'post' | 'organizerWorkspace'
  | 'marketProduct' | 'tournament' | 'news' | 'achievement';

export type LinkChannel =
  | 'whatsapp' | 'telegram' | 'facebook' | 'x' | 'sms' | 'copy_link'
  | 'system_share' | 'deep_link' | 'web_direct';

async function recordLinkEvent(params: {
  eventType: 'share' | 'click';
  entityType: LinkEntityType;
  entityId: string;
  channel: LinkChannel;
}) {
  try {
    const entityKey = params.entityId.trim();
    if (!entityKey) return;

    const uid = auth.currentUser?.uid.trim() || '';
    const now = Date.now();
    const eventRef = doc(collection(db, 'analytics_link_events'));
    const eventId = eventRef.id;

    await setDoc(eventRef, {
      eventId,
      eventType: params.eventType,
      entityType: params.entityType,
      entityId: entityKey,
      channel: params.channel,
      userId: uid,
      createdAtMs: now,
    });

    const rollupId = `${params.entityType}_${entityKey}`;
    await setDoc(
      doc(db, 'analytics_link_rollups', rollupId),
      {
        entityType: params.entityType,
        entityId: entityKey,
        ...(params.eventType === 'share' ? { shareCount: increment(1) } : { clickCount: increment(1) }),
        lastEventAtMs: now,
      },
      { merge: true },
    );
  } catch (err) {
    console.error('[linkAnalyticsService] record failed (non-fatal):', err);
  }
}

/** A deep link / public URL for this entity was opened — typically
 * 'web_direct' when landed on directly in a browser tab. */
export function recordLinkClick(entityType: LinkEntityType, entityId: string, channel: LinkChannel = 'web_direct') {
  void recordLinkEvent({ eventType: 'click', entityType, entityId, channel });
}

/** This entity was shared via the given channel. */
export function recordLinkShare(entityType: LinkEntityType, entityId: string, channel: LinkChannel) {
  void recordLinkEvent({ eventType: 'share', entityType, entityId, channel });
}
