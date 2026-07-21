'use client';

import { useEffect, useState } from 'react';
import { collection, onSnapshot, query, where } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { League } from '@/types/league';

export function useMasterLeagueTournaments(masterLeagueId: string) {
  const [leagues, setLeagues] = useState<League[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) return;
    const q = query(collection(db, 'leagues'), where('masterLeagueId', '==', masterLeagueId));
    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => ({ id: d.id, ...d.data() }) as League);
        list.sort((a: any, b: any) => (b.updatedAtMs ?? 0) - (a.updatedAtMs ?? 0));
        setLeagues(list);
        setLoading(false);
      },
      () => setLoading(false),
    );
    return () => unsub();
  }, [masterLeagueId]);

  return { leagues, loading };
}
