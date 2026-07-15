import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { League } from '@/types/league';

export function useLeagues() {
  const [leagues, setLeagues] = useState<League[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!auth.currentUser) {
      setLoading(false);
      return;
    }

    const uid = auth.currentUser.uid;

    // Fetch leagues where the user is either the owner OR in the memberIds array
    // Firestore requires separate queries for OR logic across different fields, 
    // so we listen to both and merge them client-side.
    const ownerQuery = query(collection(db, 'leagues'), where('organizerId', '==', uid));
    const memberQuery = query(collection(db, 'leagues'), where('memberIds', 'array-contains', uid));

    const handleData = () => {
      const merged = new Map<string, League>();
      ownerDocs.forEach(d => merged.set(d.id, d));
      memberDocs.forEach(d => merged.set(d.id, d));
      setLeagues(Array.from(merged.values()));
      setLoading(false);
    };

    let ownerDocs: League[] = [];
    let memberDocs: League[] = [];
    let loaded1 = false, loaded2 = false;

    const unsub1 = onSnapshot(ownerQuery, (snap) => {
      ownerDocs = snap.docs.map(d => ({ id: d.id, ...d.data() } as League));
      loaded1 = true;
      if (loaded2) handleData();
    }, (err) => setError(err.message));

    const unsub2 = onSnapshot(memberQuery, (snap) => {
      memberDocs = snap.docs.map(d => ({ id: d.id, ...d.data() } as League));
      loaded2 = true;
      if (loaded1) handleData();
    }, (err) => setError(err.message));

    return () => { unsub1(); unsub2(); };
  }, []);

  return { leagues, loading, error };
}
