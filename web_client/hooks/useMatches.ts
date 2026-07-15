import { useState, useEffect } from 'react';
import { collection, query, onSnapshot, orderBy } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { FixtureMatch } from '@/types/match';

export function useMatches(leagueId: string) {
  const [matches, setMatches] = useState<FixtureMatch[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!leagueId) return;

    // Fetch matches ordered by round and status
    const q = query(
      collection(db, 'leagues', leagueId, 'matches'),
      orderBy('roundNumber', 'asc')
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const matchesData = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as FixtureMatch[];
      
      setMatches(matchesData);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching matches:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [leagueId]);

  return { matches, loading, error };
}
