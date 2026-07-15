import { useState, useEffect } from 'react';
import { collection, query, orderBy, limit, getDocs } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MasterLeague } from '@/types/masterLeague';

export function useOrganizerDiscovery() {
  const [hubs, setHubs] = useState<MasterLeague[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchDiscovery = async () => {
      try {
        // Fetch top Hubs by follower count (matches the intent of public discovery)
        const q = query(
          collection(db, 'master_leagues'),
          orderBy('followersCount', 'desc'),
          limit(20)
        );
        const snap = await getDocs(q);
        const data = snap.docs.map(doc => ({ id: doc.id, ...doc.data() } as MasterLeague));
        setHubs(data);
      } catch (err) {
        console.error("Discovery fetch error:", err);
      } finally {
        setLoading(false);
      }
    };
    fetchDiscovery();
  }, []);

  return { hubs, loading };
}
