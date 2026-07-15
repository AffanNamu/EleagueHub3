import { useState, useEffect } from 'react';
import { collection, query, orderBy, limit, onSnapshot, where } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface Announcement {
  id: string;
  title: string;
  message: string;
  createdAtMs: number;
  pinned: boolean;
}

export function useAnnouncements(masterLeagueId: string) {
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) return;

    // Matches the Flutter logic: fetch recent announcements, prioritize pinned
    const q = query(
      collection(db, 'master_leagues', masterLeagueId, 'announcements'),
      orderBy('createdAtMs', 'desc'),
      limit(5)
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const data = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as Announcement[];
      
      // Sort pinned to top client-side to save complex composite indexes
      data.sort((a, b) => (a.pinned === b.pinned ? 0 : a.pinned ? -1 : 1));
      
      setAnnouncements(data);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [masterLeagueId]);

  return { announcements, loading };
}
