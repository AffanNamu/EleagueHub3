import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, Unsubscribe } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { LeagueData } from '@/lib/models/league';

export function useLeagues() {
  const [leagues, setLeagues] = useState<LeagueData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const unsubscribeAuth = auth.onAuthStateChanged((user) => {
      if (!user) {
        setLeagues([]);
        setLoading(false);
        return;
      }

      const uid = user.uid.trim();
      const leaguesRef = collection(db, 'leagues');

      // STRICT PARITY: Matches Flutter's `_fetchLeaguesFromFirestoreForWeb` logic.
      // Firestore requires separate queries for OR logic across different fields.
      const queries = [
        query(leaguesRef, where('memberIds', 'array-contains', uid)),
        query(leaguesRef, where('organizerUid', '==', uid)),
        query(leaguesRef, where('ownerUid', '==', uid)),
        query(leaguesRef, where('ownerId', '==', uid)),
        query(leaguesRef, where('organizerUserId', '==', uid)),
      ];

      const unsubscribes: Unsubscribe[] = [];
      const queryResults = new Map<number, LeagueData[]>();
      let loadedCount = 0;

      const handleData = () => {
        if (loadedCount < queries.length) return;
        
        const merged = new Map<string, LeagueData>();
        for (const docs of queryResults.values()) {
          docs.forEach(d => {
            // Guarantee ID exists exactly like Flutter's `map['id'] = entry.key;`
            if (!d.id) d.id = d.id; 
            merged.set(d.id, d);
          });
        }
        
        setLeagues(Array.from(merged.values()));
        setLoading(false);
      };

      queries.forEach((q, index) => {
        const unsub = onSnapshot(q, (snap) => {
          queryResults.set(
            index, 
            snap.docs.map(d => ({ id: d.id, ...d.data() } as LeagueData))
          );
          
          if (loadedCount < queries.length) {
            loadedCount++;
          }
          handleData();
        }, (err) => {
          console.error(`[useLeagues] Query ${index} failed:`, err);
          setError(err.message);
        });
        
        unsubscribes.push(unsub);
      });

      return () => {
        unsubscribes.forEach(unsub => unsub());
      };
    });

    return () => unsubscribeAuth();
  }, []);

  return { leagues, loading, error };
}
