import { useState, useEffect } from 'react';
import { collection, query, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';

export interface OrganizerFeedEvent {
  id: string;
  organizerId: string;
  organizerName: string;
  organizerLogo: string;
  type: 'announcement' | 'new_league' | 'milestone';
  title: string;
  description: string;
  targetId?: string; // e.g., the League ID
  createdAtMs: number;
}

export function useOrganizerFeed() {
  const [feed, setFeed] = useState<OrganizerFeedEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!auth.currentUser) {
      setLoading(false);
      return;
    }

    // In a fan-out architecture (common in Firebase feeds), each user has their own feed collection
    const q = query(
      collection(db, 'users', auth.currentUser.uid, 'organizer_feed'),
      orderBy('createdAtMs', 'desc'),
      limit(30)
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const data = snapshot.docs.map(doc => ({
        id: doc.id, ...doc.data()
      })) as OrganizerFeedEvent[];
      setFeed(data);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  return { feed, loading };
}
