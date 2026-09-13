// web_client/lib/social/homeContentRepository.ts
//
// Read side of the admin-controlled Home Content CMS (home_content
// collection — see esportlyic-admin/lib/repositories/homeContentAdminRepository.ts
// for the schema and write path). Filters to active items within their
// optional start/end window client-side; there's no scheduled function
// flipping `active` automatically, so an item can be active=true outside
// its window and still needs this check.

import { collection, onSnapshot, orderBy, query, where, DocumentData, Unsubscribe, doc, setDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

export type HomeContentType = 'hero' | 'promo_card' | 'announcement';
export type AnnouncementSeverity = 'info' | 'warning' | 'critical';

export interface HomeContentItem {
  id: string;
  type: HomeContentType;
  title: string;
  subtitle: string;
  imageUrl: string;
  ctaLabel: string;
  ctaRoute: string;
  severity: AnnouncementSeverity;
  order: number;
  createdAtMs: number;
}

function fromDoc(id: string, data: DocumentData): HomeContentItem {
  return {
    id,
    type: (data.type === 'hero' || data.type === 'promo_card' || data.type === 'announcement') ? data.type : 'promo_card',
    title: (data.title || '').trim(),
    subtitle: (data.subtitle || '').trim(),
    imageUrl: (data.imageUrl || '').trim(),
    ctaLabel: (data.ctaLabel || '').trim(),
    ctaRoute: (data.ctaRoute || '').trim(),
    severity: ['info', 'warning', 'critical'].includes(data.severity) ? data.severity : 'info',
    order: typeof data.order === 'number' ? data.order : 0,
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
  };
}

function isWithinWindow(data: DocumentData, nowMs: number): boolean {
  const startAtMs = typeof data.startAtMs === 'number' ? data.startAtMs : null;
  const endAtMs = typeof data.endAtMs === 'number' ? data.endAtMs : null;
  if (startAtMs != null && nowMs < startAtMs) return false;
  if (endAtMs != null && nowMs > endAtMs) return false;
  return true;
}

/** Streams active home_content items, newest-scheduled-first filtering applied client-side, ordered by `order`. */
export function watchHomeContentWeb(callback: (items: HomeContentItem[]) => void): Unsubscribe {
  const q = query(collection(db, 'home_content'), where('active', '==', true), orderBy('order', 'asc'));
  return onSnapshot(
    q,
    (snap) => {
      const nowMs = Date.now();
      const items = snap.docs
        .filter((d) => isWithinWindow(d.data(), nowMs))
        .map((d) => fromDoc(d.id, d.data()));
      callback(items);
    },
    () => callback([]),
  );
}

/** Marks the given announcement as seen by this user, mirroring markAllSeenWeb's per-user cursor pattern. */
export async function markAnnouncementSeenWeb(announcementCreatedAtMs: number): Promise<void> {
  const uid = auth.currentUser?.uid.trim() || '';
  if (!uid) return;
  try {
    await setDoc(doc(db, 'users', uid), { lastSeenHomeAnnouncementAtMs: announcementCreatedAtMs }, { merge: true });
  } catch {
    // best-effort
  }
}
