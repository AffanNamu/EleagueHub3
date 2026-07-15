import { useState, useEffect } from 'react';
import { collection, query, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { KnockoutMatch } from '@/types/match';

export function useKnockoutMatches(leagueId: string) {
  const [matches, setMatches] = useState<KnockoutMatch[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!leagueId) return;

    const q = query(collection(db, 'leagues', leagueId, 'knockout'));

    const unsubscribe = onSnapshot(q, (snapshot) => {
      let matchesData = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as KnockoutMatch[];
      
      // Mimic your Flutter sorting logic (Round of 16 -> Quarter -> Semi -> Final)
      const roundOrder = ['Play-off', 'Round of 16', 'Quarter Finals', 'Semi Finals', '3rd Place', 'Final'];
      
      matchesData.sort((a, b) => {
        const ai = roundOrder.indexOf(a.roundName);
        const bi = roundOrder.indexOf(b.roundName);
        if (ai !== bi) return ai - bi;
        return a.id.localeCompare(b.id);
      });

      setMatches(matchesData);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching knockout matches:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [leagueId]);

  return { matches, loading, error };
}
