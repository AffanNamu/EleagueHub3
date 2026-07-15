import { useState, useEffect } from 'react';
import { collection, query, onSnapshot, orderBy } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { Team } from '@/types/league';

export function useLeagueTeams(leagueId: string) {
  const [teams, setTeams] = useState<Team[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!leagueId) return;

    // Fetch teams for this specific league, ordered by points descending
    const q = query(
      collection(db, 'leagues', leagueId, 'teams'),
      orderBy('finalPoints', 'desc'),
      orderBy('goalDifference', 'desc'),
      orderBy('goalsFor', 'desc')
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const teamsData = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as Team[];
      
      setTeams(teamsData);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching teams:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [leagueId]);

  return { teams, loading, error };
}
