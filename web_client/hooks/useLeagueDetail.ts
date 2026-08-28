import { useState, useEffect } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { LeagueData } from '@/lib/models/league';

export function useLeagueDetail(leagueId: string) {
  const [league, setLeague] = useState<LeagueData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!leagueId) return;

    const docRef = doc(db, 'leagues', leagueId);
    const unsubscribe = onSnapshot(docRef, (docSnap) => {
      if (docSnap.exists()) {
        const data = docSnap.data();
        setLeague({ id: docSnap.id, ...data } as LeagueData);
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
