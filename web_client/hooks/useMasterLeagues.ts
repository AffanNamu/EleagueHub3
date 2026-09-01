import { useState, useEffect } from 'react';
import { collection, doc, query, where, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MasterLeagueData } from '@/lib/masterLeagues/masterLeaguesRepository';
import { LeagueData, leagueFromRemoteMap } from '@/lib/models/league';

export function useMyMasterLeagues(authUid: string | null) {
  const [created, setCreated] = useState<MasterLeagueData[]>([]);
  const [joined, setJoined] = useState<MasterLeagueData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!authUid) {
      setLoading(false);
      return;
    }

    const unsub = onSnapshot(collection(db, 'master_leagues'), (snap) => {
      const all = snap.docs.map(d => ({ id: d.id, ...d.data() } as MasterLeagueData));
      
      const myCreated = all.filter(ml => ml.ownerId === authUid).sort((a,b) => b.updatedAtMs - a.updatedAtMs);
      const myJoined = all.filter(ml => ml.ownerId !== authUid && (ml.memberIds?.includes(authUid) || ml.roles?.[authUid])).sort((a,b) => b.updatedAtMs - a.updatedAtMs);
      
      setCreated(myCreated);
      setJoined(myJoined);
      setLoading(false);
    });

    return () => unsub();
  }, [authUid]);

  return { created, joined, loading };
}

export function useMasterLeagueDetails(mlId: string) {
  const [masterLeague, setMasterLeague] = useState<MasterLeagueData | null>(null);
  const [childLeagues, setChildLeagues] = useState<LeagueData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!mlId) return;

    // Watch Master League Document
    const unsubML = onSnapshot(doc(db, 'master_leagues', mlId), (d) => {
      if (d.exists()) setMasterLeague({ id: d.id, ...d.data() } as MasterLeagueData);
      else setMasterLeague(null);
    });

    // Watch Child Competitions linked to this workspace
    const q = query(collection(db, 'leagues'), where('masterLeagueId', '==', mlId));
    const unsubLeagues = onSnapshot(q, (snap) => {
      const list = snap.docs.map(d => leagueFromRemoteMap({ id: d.id, ...d.data() })).sort((a,b) => b.updatedAtMs - a.updatedAtMs);
      setChildLeagues(list);
      setLoading(false);
    });

    return () => { unsubML(); unsubLeagues(); };
  }, [mlId]);

  return { masterLeague, childLeagues, loading };
}
