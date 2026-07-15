import { useState, useEffect } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MasterLeague } from '@/types/masterLeague';

export function useMasterLeagueDetail(id: string) {
  const [workspace, setWorkspace] = useState<MasterLeague | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;

    const docRef = doc(db, 'master_leagues', id);
    const unsubscribe = onSnapshot(docRef, (docSnap) => {
      if (docSnap.exists()) {
        setWorkspace({ id: docSnap.id, ...docSnap.data() } as MasterLeague);
      } else {
        setError('Workspace not found');
      }
      setLoading(false);
    }, (err) => {
      console.error("Error fetching workspace details:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [id]);

  return { workspace, loading, error };
}
