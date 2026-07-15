import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, orderBy } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { MasterLeague } from '@/types/masterLeague';

export function useMasterLeagues(filterOwned: boolean = false) {
  const [workspaces, setWorkspaces] = useState<MasterLeague[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let q = query(collection(db, 'master_leagues'), orderBy('followersCount', 'desc'));

    if (filterOwned && auth.currentUser) {
      q = query(
        collection(db, 'master_leagues'),
        where('ownerId', '==', auth.currentUser.uid)
      );
    }

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const data = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      })) as MasterLeague[];
      
      setWorkspaces(data);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching workspaces:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [filterOwned]);

  return { workspaces, loading, error };
}
