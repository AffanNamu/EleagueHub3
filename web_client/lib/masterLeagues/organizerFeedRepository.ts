// lib/masterLeagues/organizerFeedRepository.ts
//
// Mirrors lib/features/master_leagues/data/organizer_feed_firebase.dart +
// domain/organizer_feed_event.dart. Backs the "Followed Organizer Feed"
// screen — a shared activity feed of events (competition created, organizer
// announcement posted, verification approved/renewed) scoped to whichever
// Master League workspaces the signed-in user follows (master_leagues/{id}/
// followers/{uid} docs), found via a 'followers' collection-group query.

import {
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  query,
  where,
  orderBy,
  limit as fsLimit,
  setDoc,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { v4 as uuidv4 } from 'uuid';

export type OrganizerFeedEventType =
  | 'announcement'
  | 'competition_created'
  | 'verification_approved'
  | 'verification_renewed'
  | string;

export interface OrganizerFeedEvent {
  id: string;
  masterLeagueId: string;
  type: OrganizerFeedEventType;
  title: string;
  message: string;
  createdAtMs: number;
  actorId: string;
  actorName: string;
  leagueId: string;
}

function str(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

export function organizerFeedEventFromMap(map: Record<string, unknown>): OrganizerFeedEvent {
  return {
    id: str(map.id) || str(map.feedId),
    masterLeagueId: str(map.masterLeagueId),
    type: str(map.type),
    title: str(map.title),
    message: str(map.message),
    createdAtMs: Number(map.createdAtMs) || 0,
    actorId: str(map.actorId),
    actorName: str(map.actorName),
    leagueId: str(map.leagueId),
  };
}

// ── Writing events ───────────────────────────────────────────────────────
// Firestore rules require exactly these 8 keys and isMasterLeagueOwner() —
// only the workspace owner/admin who triggered the action can write.

async function addEvent(event: Omit<OrganizerFeedEvent, 'id'> & { id?: string }): Promise<void> {
  const id = (event.id || '').trim() || uuidv4();
  await setDoc(doc(db, 'organizer_feed', id), {
    id,
    masterLeagueId: event.masterLeagueId,
    type: event.type,
    title: event.title,
    message: event.message,
    createdAtMs: event.createdAtMs,
    actorId: event.actorId,
    actorName: event.actorName,
    leagueId: event.leagueId,
  });
}

export async function addAnnouncementPostedEvent({
  masterLeagueId, actorId, actorName, title,
}: {
  masterLeagueId: string; actorId: string; actorName: string; title: string;
}): Promise<void> {
  await addEvent({
    masterLeagueId: masterLeagueId.trim(),
    type: 'announcement',
    title: 'Organizer announcement posted',
    message: title.trim(),
    createdAtMs: Date.now(),
    actorId: actorId.trim(),
    actorName: actorName.trim(),
    leagueId: '',
  });
}

export async function addCompetitionCreatedEvent({
  masterLeagueId, leagueId, actorId, actorName, competitionName,
}: {
  masterLeagueId: string; leagueId: string; actorId: string; actorName: string; competitionName: string;
}): Promise<void> {
  await addEvent({
    masterLeagueId: masterLeagueId.trim(),
    type: 'competition_created',
    title: 'New competition created',
    message: competitionName.trim(),
    createdAtMs: Date.now(),
    actorId: actorId.trim(),
    actorName: actorName.trim(),
    leagueId: leagueId.trim(),
  });
}

// ── Reading the followed feed ────────────────────────────────────────────

export async function fetchFollowedOrganizerFeedOnce(userId: string): Promise<OrganizerFeedEvent[]> {
  const uid = userId.trim();
  if (!uid) return [];

  try {
    const followSnap = await getDocs(query(collectionGroup(db, 'followers'), where('userId', '==', uid)));

    const workspaceIds = Array.from(
      new Set(
        followSnap.docs
          .map((d) => d.ref.parent.parent?.id?.trim() || '')
          .filter((id) => id.length > 0),
      ),
    );

    if (workspaceIds.length === 0) return [];

    const results: OrganizerFeedEvent[] = [];
    const chunkSize = 10;

    for (let i = 0; i < workspaceIds.length; i += chunkSize) {
      const chunk = workspaceIds.slice(i, i + chunkSize);
      try {
        const feedSnap = await getDocs(
          query(
            collection(db, 'organizer_feed'),
            where('masterLeagueId', 'in', chunk),
            orderBy('createdAtMs', 'desc'),
            fsLimit(50),
          ),
        );
        feedSnap.forEach((d) => results.push(organizerFeedEventFromMap(d.data())));
      } catch (e) {
        console.warn('[organizerFeedRepository] feed chunk query failed:', e);
      }
    }

    results.sort((a, b) => b.createdAtMs - a.createdAtMs);
    return results.slice(0, 100);
  } catch (e) {
    console.warn('[organizerFeedRepository] fetchFollowedOrganizerFeedOnce failed:', e);
    return [];
  }
}

// ── Per-user read/clear cursors ──────────────────────────────────────────
// Shared organizer_feed docs can't carry per-viewer "read" state, so it
// lives on users/{uid}/private/app_state instead — the same doc mobile's
// FollowedOrganizerNotificationsService writes lastSeenOrganizerFeedAtMs to.

export interface OrganizerFeedCursors {
  lastReadAtMs: number;
  clearedAtMs: number;
}

function appStateDocRef(uid: string) {
  return doc(db, 'users', uid, 'private', 'app_state');
}

export async function getFeedCursors(uid: string): Promise<OrganizerFeedCursors> {
  const id = uid.trim();
  if (!id) return { lastReadAtMs: 0, clearedAtMs: 0 };

  try {
    const snap = await getDoc(appStateDocRef(id));
    const data = snap.data() ?? {};
    return {
      lastReadAtMs: Number(data.lastSeenOrganizerFeedAtMs) || 0,
      clearedAtMs: Number(data.clearedOrganizerFeedAtMs) || 0,
    };
  } catch (e) {
    console.warn('[organizerFeedRepository] getFeedCursors failed:', e);
    return { lastReadAtMs: 0, clearedAtMs: 0 };
  }
}

export async function markAllRead(uid: string): Promise<number> {
  const id = uid.trim();
  if (!id) return 0;
  const now = Date.now();
  try {
    await setDoc(appStateDocRef(id), { lastSeenOrganizerFeedAtMs: now }, { merge: true });
  } catch (e) {
    console.warn('[organizerFeedRepository] markAllRead failed:', e);
  }
  return now;
}

export async function clearAllFeed(uid: string): Promise<number> {
  const id = uid.trim();
  if (!id) return 0;
  const now = Date.now();
  try {
    await setDoc(appStateDocRef(id), { clearedOrganizerFeedAtMs: now }, { merge: true });
  } catch (e) {
    console.warn('[organizerFeedRepository] clearAllFeed failed:', e);
  }
  return now;
}
