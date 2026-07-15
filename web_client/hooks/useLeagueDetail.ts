import { useState, useEffect } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { League } from '@/types/league';

export function useLeagueDetail(leagueId: string) {
  const [league, setLeague] = useState<League | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!leagueId) return;

    const docRef = doc(db, 'leagues', leagueId);
    const unsubscribe = onSnapshot(docRef, (docSnap) => {
      if (docSnap.exists()) {
        setLeague({ id: docSnap.id, ...docSnap.data() } as League);
      } else {
        setError('League not found');
      }
      setLoading(false);
    }, (err) => {
      console.error("Error fetching league details:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [leagueId]);

  return { league, loading, error };
}
