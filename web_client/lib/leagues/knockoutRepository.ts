// lib/leagues/knockoutRepository.ts
//
// Firestore I/O for leagues/{leagueId}/knockout — no equivalent existed on
// web before this (the generate-knockout buttons never read or wrote
// anything). Mirrors LocalLeaguesRepository.getKnockoutMatches /
// saveKnockoutMatches on the Flutter side.

import { collection, getDocs, doc, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { KnockoutMatch } from '@/lib/algorithms/tournamentController';

export async function fetchKnockoutMatches(leagueId: string): Promise<KnockoutMatch[]> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'knockout'));
  return snap.docs.map((d) => ({ ...(d.data() as object), id: d.id } as KnockoutMatch));
}

export async function saveKnockoutMatches(leagueId: string, matches: KnockoutMatch[]): Promise<void> {
  // Firestore batches are capped at 500 writes; chunk defensively even
  // though the largest bracket here (World Cup 48) is well under that.
  const chunkSize = 400;
  for (let i = 0; i < matches.length; i += chunkSize) {
    const batch = writeBatch(db);
    const chunk = matches.slice(i, i + chunkSize);
    for (const m of chunk) {
      batch.set(doc(db, 'leagues', leagueId, 'knockout', m.id), m, { merge: true });
    }
    await batch.commit();
  }
}
