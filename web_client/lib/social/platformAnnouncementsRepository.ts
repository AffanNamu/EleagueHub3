// web_client/lib/social/platformAnnouncementsRepository.ts
//
// Web port of lib/features/social/data/platform_announcements_repository.dart.
// Schema (platform_announcements/{id}): title, message, severity
// ('info'|'warning'|'critical'), active (bool), createdAtMs, createdBy.
// Unread tracking is a single per-user cursor — users/{uid}.lastSeenAnnouncementAtMs —
// bumped by markAllSeenWeb(), same model as the Dart repository.

import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
  limit as fbLimit,
  setDoc,
  where,
  DocumentData,
  Unsubscribe,
} from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

export interface PlatformAnnouncement {
  id: string;
  title: string;
  message: string;
  severity: 'info' | 'warning' | 'critical';
  createdAtMs: number;
}

const RECENT_LIMIT = 30;

function fromDoc(id: string, data: DocumentData): PlatformAnnouncement {
  return {
    id,
    title: (data.title || '').trim(),
    message: (data.message || '').trim(),
    severity: (data.severity || 'info').trim(),
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
  };
}

/** Streams up to the 30 most recent active announcements, newest first. */
export function watchRecentAnnouncementsWeb(
  callback: (items: PlatformAnnouncement[]) => void,
  maxItems = RECENT_LIMIT,
): Unsubscribe {
  const q = query(
    collection(db, 'platform_announcements'),
    where('active', '==', true),
    orderBy('createdAtMs', 'desc'),
    fbLimit(maxItems),
  );
  return onSnapshot(
    q,
    (snap) => callback(snap.docs.map((d) => fromDoc(d.id, d.data()))),
    () => callback([]),
  );
}

/** Marks all currently-visible announcements as seen by bumping the per-user cursor to now. */
export async function markAllSeenWeb(): Promise<void> {
  const uid = auth.currentUser?.uid.trim() || '';
  if (!uid) return;
  try {
    await setDoc(doc(db, 'users', uid), { lastSeenAnnouncementAtMs: Date.now() }, { merge: true });
  } catch {
    // best-effort, mirrors the Dart repository
  }
}
