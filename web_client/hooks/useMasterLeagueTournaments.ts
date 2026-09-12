'use client';

import { useEffect, useState } from 'react';
import { collection, onSnapshot, query, where } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { LeagueData, leagueFromRemoteMap } from '@/lib/models/league';

export function useMasterLeagueTournaments(masterLeagueId: string) {
  const [leagues, setLeagues] = useState<LeagueData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) return;
    const q = query(collection(db, 'leagues'), where('masterLeagueId', '==', masterLeagueId));
    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => leagueFromRemoteMap({ ...d.data(), id: d.id }));
        list.sort((a, b) => (b.updatedAtMs ?? 0) - (a.updatedAtMs ?? 0));
        setLeagues(list);
        setLoading(false);
      },
      () => setLoading(false),
    );
    return () => unsub();
  }, [masterLeagueId]);

  return { leagues, loading };
}
