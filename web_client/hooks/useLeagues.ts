import { useState, useEffect } from 'react';
import { collection, query, where, onSnapshot, Unsubscribe } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { LeagueData, leagueFromRemoteMap } from '@/lib/models/league';

export function useLeagues() {
  const [leagues, setLeagues] = useState<LeagueData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // auth.onAuthStateChanged does NOT use a listener callback's return
    // value for cleanup (it's a plain observer, not an effect) — a
    // `return () => {...}` written inside that callback, as this used to
    // do, is silently discarded and never runs. onAuthStateChanged fires
    // more than once per session (at least once on mount and again once
    // Firebase finishes restoring persisted auth, plus again on token
    // refresh/tab visibility changes), so every re-fire was piling on
    // another 5 live Firestore listeners with the previous batch never
    // torn down — an unbounded listener leak that compounds over a
    // session and was the real cause of /leagues eventually crashing the
    // tab. Track the current batch outside the callback instead, and
    // tear it down both before starting a new batch and on unmount.
    let activeUnsubscribes: Unsubscribe[] = [];

    function teardownActiveListeners() {
      activeUnsubscribes.forEach((unsub) => unsub());
      activeUnsubscribes = [];
    }

    const unsubscribeAuth = auth.onAuthStateChanged((user) => {
      teardownActiveListeners();

      if (!user) {
        setLeagues([]);
        setLoading(false);
        return;
      }

      const uid = user.uid.trim();
      const leaguesRef = collection(db, 'leagues');

      // STRICT PARITY: Matches Flutter's `_fetchLeaguesFromFirestoreForWeb` logic.
      // Firestore requires separate queries for OR logic across different fields.
      const queries = [
        query(leaguesRef, where('memberIds', 'array-contains', uid)),
        query(leaguesRef, where('organizerUid', '==', uid)),
        query(leaguesRef, where('ownerUid', '==', uid)),
        query(leaguesRef, where('ownerId', '==', uid)),
        query(leaguesRef, where('organizerUserId', '==', uid)),
      ];

      const queryResults = new Map<number, LeagueData[]>();
      let loadedCount = 0;

      const handleData = () => {
        if (loadedCount < queries.length) return;

        const merged = new Map<string, LeagueData>();
        for (const docs of queryResults.values()) {
          docs.forEach(d => merged.set(d.id, d));
        }

        setLeagues(Array.from(merged.values()));
        setLoading(false);
      };

      activeUnsubscribes = queries.map((q, index) =>
        onSnapshot(q, (snap) => {
          // Raw-casting `{ id: d.id, ...d.data() } as LeagueData` (the
          // previous code here) skips leagueFromRemoteMap's normalization
          // entirely — footballCategory stays the raw Firestore storage
          // string (e.g. "Local Football") instead of the union key
          // (e.g. "localFootball"), and format stays the raw numeric
          // index instead of the string union. categoryEmoji/categoryLabel
          // in LeagueCard then index CATEGORY_META by that raw value,
          // which isn't a valid key, and throw reading .emoji/.label off
          // undefined — an uncaught render-time crash the instant a real
          // league (not the loading skeleton) renders.
          queryResults.set(
            index,
            snap.docs.map(d => leagueFromRemoteMap({ ...d.data(), id: d.id }))
          );

          if (loadedCount < queries.length) {
            loadedCount++;
          }
          handleData();
        }, (err) => {
          console.error(`[useLeagues] Query ${index} failed:`, err);
          setError(err.message);
        })
      );
    });

    return () => {
      unsubscribeAuth();
      teardownActiveListeners();
    };
  }, []);

  return { leagues, loading, error };
}
