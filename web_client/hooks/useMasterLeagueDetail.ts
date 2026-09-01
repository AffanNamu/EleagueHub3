import { useState, useEffect } from 'react';
import { doc, onSnapshot, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { toggleFollowWorkspaceWeb } from '@/lib/masterLeagues/masterLeaguesRepository';
import { MasterLeagueData } from '@/lib/masterLeagues/masterLeaguesRepository';

export async function followWorkspace(mlId: string, authUid: string) {
  return toggleFollowWorkspaceWeb(mlId, authUid, false);
}

export async function unfollowWorkspace(mlId: string, authUid: string) {
  return toggleFollowWorkspaceWeb(mlId, authUid, true);
}

export async function isFollowing(mlId: string, authUid: string) {
  const snap = await getDoc(doc(db, 'master_leagues', mlId, 'followers', authUid));
  return snap.exists();
}

export function useMasterLeagueDetail(masterLeagueId: string) {
  const [workspace, setWorkspace] = useState<MasterLeagueData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) return;
    const unsub = onSnapshot(doc(db, 'master_leagues', masterLeagueId), (d) => {
      if (d.exists()) setWorkspace({ id: d.id, ...d.data() } as MasterLeagueData);
      else setWorkspace(null);
      setLoading(false);
    });
    return () => unsub();
  }, [masterLeagueId]);

  return { workspace, loading };
}
