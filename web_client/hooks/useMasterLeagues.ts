'use client';

import { useEffect, useState, useCallback } from 'react';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { MasterLeague } from '@/types/masterLeague';
import { discoverAll, fetchCreated, fetchJoined } from '@/lib/masterLeagues/masterLeaguesRepository';

/**
 * mineOnly = true  -> returns { created, joined } for the signed-in user
 * mineOnly = false -> returns public discovery list in `workspaces`
 */
export function useMasterLeagues(mineOnly: boolean) {
  const [workspaces, setWorkspaces] = useState<MasterLeague[]>([]);
  const [created, setCreated] = useState<MasterLeague[]>([]);
  const [joined, setJoined] = useState<MasterLeague[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      if (mineOnly) {
        const uid = auth.currentUser?.uid;
        if (!uid) {
          setCreated([]);
          setJoined([]);
          return;
        }
        const [c, j] = await Promise.all([fetchCreated(uid), fetchJoined(uid)]);
        setCreated(c);
        setJoined(j);
      } else {
        const all = await discoverAll(20);
        setWorkspaces(all);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [mineOnly]);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, () => load());
    return () => unsub();
  }, [load]);

  return { workspaces, created, joined, loading, error, refresh: load };
}
