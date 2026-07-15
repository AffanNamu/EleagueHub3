import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, orderBy } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { LiveSession } from '@/types/live';

export function useLiveSessions() {
  const [sessions, setSessions] = useState<LiveSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Fetch all currently active live sessions across leagues
    const q = query(
      collection(db, 'live_sessions'),
      where('isLive', '==', true),
      orderBy('createdAt', 'desc')
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const activeSessions = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as LiveSession[];
      
      setSessions(activeSessions);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching live sessions:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  return { sessions, loading, error };
}
