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
      
      // Strict Parity with Flutter: Round of 32 added for World Cup format
      const roundOrder = ['Play-off', 'Round of 32', 'Round of 16', 'Quarter Finals', 'Semi Finals', '3rd Place', 'Final'];
      
      matchesData.sort((a, b) => {
        const ai = roundOrder.indexOf(a.roundName);
        const bi = roundOrder.indexOf(b.roundName);
        if (ai !== bi) return ai - bi;
        return (a.id || '').localeCompare(b.id || '');
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
