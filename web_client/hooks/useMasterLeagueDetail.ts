'use client';

import { useEffect, useState, useCallback } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { onAuthStateChanged } from 'firebase/auth';
import { db, auth } from '@/lib/firebase';
import { MasterLeague, masterLeagueFromDoc } from '@/types/masterLeague';
import { followWorkspace, isFollowing, unfollowWorkspace } from '@/lib/masterLeagues/masterLeaguesRepository';

export function useMasterLeagueDetail(masterLeagueId: string) {
  const [workspace, setWorkspace] = useState<MasterLeague | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [following, setFollowing] = useState(false);
  const [followBusy, setFollowBusy] = useState(false);
  const [uid, setUid] = useState<string>('');

  useEffect(() => {
    if (!masterLeagueId) return;
    const ref = doc(db, 'master_leagues', masterLeagueId);
    const unsub = onSnapshot(
      ref,
      (snap) => {
        if (!snap.exists()) {
          setWorkspace(null);
        } else {
          setWorkspace(masterLeagueFromDoc(snap.id, snap.data()));
        }
        setLoading(false);
      },
      (err) => {
        setError(err.message);
        setLoading(false);
      },
    );
    return () => unsub();
  }, [masterLeagueId]);

  useEffect(() => {
    return onAuthStateChanged(auth, async (user) => {
      setUid(user?.uid ?? '');
      if (user && masterLeagueId) {
        setFollowing(await isFollowing(masterLeagueId, user.uid));
      } else {
        setFollowing(false);
      }
    });
  }, [masterLeagueId]);

  const toggleFollow = useCallback(async () => {
    if (followBusy || !masterLeagueId) return;
    setFollowBusy(true);
    try {
      if (following) {
        await unfollowWorkspace(masterLeagueId);
        setFollowing(false);
      } else {
        await followWorkspace(masterLeagueId);
        setFollowing(true);
      }
    } finally {
      setFollowBusy(false);
    }
  }, [following, followBusy, masterLeagueId]);

  return { workspace, loading, error, uid, following, followBusy, toggleFollow };
}
