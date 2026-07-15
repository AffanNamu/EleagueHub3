import { useState, useEffect } from 'react';
import { collection, query, where, getDocs } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { League } from '@/types/league';

export function useMasterLeagueTournaments(masterLeagueId: string) {
  const [leagues, setLeagues] = useState<League[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) {
      setLoading(false);
      return;
    }
    const fetchLeagues = async () => {
      try {
        const q = query(collection(db, 'leagues'), where('masterLeagueId', '==', masterLeagueId));
        const snap = await getDocs(q);
        const data = snap.docs.map(doc => ({ id: doc.id, ...doc.data() } as League));
        setLeagues(data);
      } catch (err) {
        console.error("Failed to fetch tournaments:", err);
      } finally {
        setLoading(false);
      }
    };
    fetchLeagues();
  }, [masterLeagueId]);

  return { leagues, loading };
}
