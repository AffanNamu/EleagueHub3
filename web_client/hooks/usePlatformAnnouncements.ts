import { useState, useEffect } from 'react';
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface PlatformAnnouncement {
  id: string;
  title: string;
  message: string;
  type: 'update' | 'alert' | 'maintenance';
  createdAtMs: number;
  authorName: string;
}

export function usePlatformAnnouncements(maxItems = 3) {
  const [announcements, setAnnouncements] = useState<PlatformAnnouncement[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(
      collection(db, 'platform_announcements'),
      orderBy('createdAtMs', 'desc'),
      limit(maxItems)
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const data = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as PlatformAnnouncement[];
      
      setAnnouncements(data);
      setLoading(false);
    }, (error) => {
      console.error("Error fetching platform announcements:", error);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [maxItems]);

  return { announcements, loading };
}
