// lib/masterLeagues/masterLeagueAnnouncementsRepository.ts
//
// Mirrors lib/features/leagues/data/league_announcements_firebase.dart's
// master-league methods (addMasterLeagueAnnouncement/pin/unpin/delete) and
// master_league_details_screen.dart's usage of them. Writes to
// master_leagues/{id}/announcements — a DIFFERENT, stricter-schema
// subcollection than leagues/{id}/announcements (League-level, handled by
// leagueAdminRepository.ts's sendAnnouncementWeb): the Firestore rules here
// require exactly 11 keys and no 'id'/'scope' field, unlike the permissive
// League-announcement rule.

import { collection, doc, getDocs, onSnapshot, orderBy, query, setDoc, updateDoc, deleteDoc, where, writeBatch } from 'firebase/firestore';
import { useEffect, useState } from 'react';
import { db } from '@/lib/firebase';
import { LeagueAnnouncement } from '@/lib/models/leagueDetails';
import { addAnnouncementPostedEvent } from '@/lib/masterLeagues/organizerFeedRepository';

function announcementsCol(masterLeagueId: string) {
  return collection(db, 'master_leagues', masterLeagueId.trim(), 'announcements');
}

function announcementFromDoc(id: string, data: Record<string, unknown>): LeagueAnnouncement {
  return {
    id,
    leagueId: String(data.leagueId ?? '').trim(),
    masterLeagueId: String(data.masterLeagueId ?? '').trim(),
    scope: 'master_league',
    title: String(data.title ?? '').trim(),
    message: String(data.message ?? '').trim(),
    createdAtMs: Number(data.createdAtMs) || 0,
    authorId: String(data.authorId ?? '').trim(),
    authorName: String(data.authorName ?? '').trim(),
    pinned: data.pinned === true,
    pinnedAtMs: Number(data.pinnedAtMs) || 0,
    pinnedBy: String(data.pinnedBy ?? '').trim(),
  };
}

// ── Real-time list (newest first) ────────────────────────────────────────

export function useMasterLeagueAnnouncements(masterLeagueId: string) {
  const [announcements, setAnnouncements] = useState<LeagueAnnouncement[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const id = masterLeagueId.trim();
    if (!id) {
      const timer = setTimeout(() => {
        setAnnouncements([]);
        setLoading(false);
      }, 0);
      return () => clearTimeout(timer);
    }

    const q = query(announcementsCol(id), orderBy('createdAtMs', 'desc'));
    const unsub = onSnapshot(
      q,
      (snap) => {
        setAnnouncements(snap.docs.map((d) => announcementFromDoc(d.id, d.data())));
        setLoading(false);
      },
      (err) => {
        console.warn('[masterLeagueAnnouncementsRepository] watch failed:', err);
        setAnnouncements([]);
        setLoading(false);
      },
    );
    return () => unsub();
  }, [masterLeagueId]);

  return { announcements, loading };
}

// ── Post ──────────────────────────────────────────────────────────────────

export async function addMasterLeagueAnnouncementWeb({
  masterLeagueId, title, message, authorId, authorName,
}: {
  masterLeagueId: string; title: string; message: string; authorId: string; authorName: string;
}): Promise<void> {
  const mlId = masterLeagueId.trim();
  const now = Date.now();

  const ref = doc(announcementsCol(mlId));
  await setDoc(ref, {
    masterLeagueId: mlId,
    leagueId: '',
    title: title.trim(),
    message: message.trim(),
    authorId: authorId.trim(),
    authorName: authorName.trim(),
    pinned: false,
    pinnedBy: '',
    pinnedAtMs: 0,
    createdAtMs: now,
    updatedAtMs: now,
  });

  // Non-fatal: lets followers see this in their Followed Organizer Feed.
  try {
    await addAnnouncementPostedEvent({ masterLeagueId: mlId, actorId: authorId, actorName: authorName, title });
  } catch (e) {
    console.warn('[masterLeagueAnnouncementsRepository] addAnnouncementPostedEvent failed (non-fatal):', e);
  }
}

// ── Pin / unpin ───────────────────────────────────────────────────────────
// Only one announcement can be pinned at a time — pinning a new one first
// unpins whatever was previously pinned, in the same batch.

export async function pinMasterLeagueAnnouncementWeb({
  masterLeagueId, announcementId, pinnedBy,
}: {
  masterLeagueId: string; announcementId: string; pinnedBy: string;
}): Promise<void> {
  const mlId = masterLeagueId.trim();
  const col = announcementsCol(mlId);

  const existing = await getDocs(query(col, where('pinned', '==', true)));
  const batch = writeBatch(db);
  existing.forEach((d) => {
    batch.update(d.ref, { pinned: false, pinnedBy: '', pinnedAtMs: 0 });
  });
  batch.update(doc(col, announcementId), {
    pinned: true,
    pinnedBy: pinnedBy.trim(),
    pinnedAtMs: Date.now(),
  });
  await batch.commit();
}

export async function unpinMasterLeagueAnnouncementWeb({
  masterLeagueId, announcementId,
}: {
  masterLeagueId: string; announcementId: string;
}): Promise<void> {
  await updateDoc(doc(announcementsCol(masterLeagueId.trim()), announcementId), {
    pinned: false,
    pinnedBy: '',
    pinnedAtMs: 0,
  });
}

// ── Delete ────────────────────────────────────────────────────────────────

export async function deleteMasterLeagueAnnouncementWeb({
  masterLeagueId, announcementId,
}: {
  masterLeagueId: string; announcementId: string;
}): Promise<void> {
  await deleteDoc(doc(announcementsCol(masterLeagueId.trim()), announcementId));
}
