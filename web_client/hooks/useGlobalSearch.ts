import { useState, useEffect } from 'react';
import { collection, query, where, getDocs, limit } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { League } from '@/types/league';
import { MasterLeague } from '@/types/masterLeague';
import { searchUsers, UserSearchEntry } from '@/lib/services/userSearchRepository';

export function useGlobalSearch(searchTerm: string) {
  const [leagues, setLeagues] = useState<League[]>([]);
  const [masterLeagues, setMasterLeagues] = useState<MasterLeague[]>([]);
  const [users, setUsers] = useState<UserSearchEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const performSearch = async () => {
      if (!searchTerm || searchTerm.length < 2) {
        setLeagues([]);
        setMasterLeagues([]);
        setUsers([]);
        return;
      }

      setLoading(true);
      setError(null);

      // Capitalize first letter to match common Firestore storage patterns 
      // (For production, you might want lowercase normalized fields)
      const term = searchTerm; 
      const endTerm = term + '\uf8ff';

      try {
        // 1. Search Leagues
        const leaguesQ = query(
          collection(db, 'leagues'),
          where('name', '>=', term),
          where('name', '<=', endTerm),
          limit(10)
        );

        // 2. Search Master Leagues (Workspaces)
        const masterQ = query(
          collection(db, 'master_leagues'),
          where('name', '>=', term),
          where('name', '<=', endTerm),
          limit(10)
        );

        const [leaguesSnap, masterSnap, usersResult] = await Promise.all([
          getDocs(leaguesQ),
          getDocs(masterQ),
          // NEW: user search, so people can find and message each other.
          searchUsers(term),
        ]);

        setLeagues(leaguesSnap.docs.map(d => ({ id: d.id, ...d.data() } as League)));
        setMasterLeagues(masterSnap.docs.map(d => ({ id: d.id, ...d.data() } as MasterLeague)));
        setUsers(usersResult);

      } catch (err: any) {
        console.error("Search Error:", err);
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    const delayDebounceFn = setTimeout(() => {
      performSearch();
    }, 500); // 500ms debounce to prevent spamming Firestore reads

    return () => clearTimeout(delayDebounceFn);
  }, [searchTerm]);

  return { leagues, masterLeagues, users, loading, error };
}