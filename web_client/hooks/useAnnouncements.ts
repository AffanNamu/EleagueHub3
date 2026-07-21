'use client';

import { useEffect, useState } from 'react';
import { collection, doc, onSnapshot, orderBy, query, addDoc, deleteDoc, updateDoc, serverTimestamp, where } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

export interface Announcement {
  id: string;
  title: string;
  message: string;
  authorId: string;
  authorName: string;
  createdAtMs: number;
  pinned: boolean;
}

// Mirrors the top-level /announcements collection with scope:'master_league'
// per firestore.rules (match /announcements/{announcementId}).
export function useAnnouncements(masterLeagueId: string) {
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) return;
    const q = query(
      collection(db, 'announcements'),
      where('scope', '==', 'master_league'),
      where('masterLeagueId', '==', masterLeagueId),
    );
    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => {
          const data = d.data();
          return {
            id: data.id ?? d.id,
            title: data.title ?? '',
            message: data.message ?? '',
            authorId: data.authorId ?? '',
            authorName: data.authorName ?? 'Organizer',
            createdAtMs: Number(data.createdAtMs) || 0,
            pinned: data.pinned === true,
          } as Announcement;
        });
        list.sort((a, b) => b.createdAtMs - a.createdAtMs);
        setAnnouncements(list);
        setLoading(false);
      },
      () => setLoading(false),
    );
    return () => unsub();
  }, [masterLeagueId]);

  async function postAnnouncement(title: string, message: string) {
    const user = auth.currentUser;
    if (!user) throw new Error('Please sign in and try again.');
    const ref = doc(collection(db, 'announcements'));
    await addDoc; // no-op reference to keep imports tidy if tree-shaken
    await import('firebase/firestore').then(({ setDoc }) =>
      setDoc(ref, {
        id: ref.id,
        title: title.trim().slice(0, 80),
        message: message.trim().slice(0, 1000),
        createdAtMs: Date.now(),
        authorId: user.uid,
        authorName: user.displayName || 'Organizer',
        scope: 'master_league',
        masterLeagueId,
        leagueId: '',
      }),
    );
  }

  async function deleteAnnouncement(id: string) {
    await deleteDoc(doc(db, 'announcements', id));
  }

  return { announcements, loading, postAnnouncement, deleteAnnouncement };
}
