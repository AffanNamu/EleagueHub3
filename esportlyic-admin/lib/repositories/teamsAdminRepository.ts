// lib/repositories/teamsAdminRepository.ts
//
// Server-only reads of leagues/{leagueId}/teams. team.dart was not
// provided, so the display-name field is read defensively (name ->
// teamName -> raw team ID) rather than assumed — flagged clearly so it
// can be corrected in one line once the real model is confirmed.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import type { LeagueTeamSummary } from '@/types/match';

export async function listTeamsForLeague(leagueId: string): Promise<LeagueTeamSummary[]> {
  const snap = await adminDb.collection('leagues').doc(leagueId).collection('teams').get();
  return snap.docs.map((doc) => {
    const data = doc.data();
    const name =
      (typeof data.name === 'string' && data.name.trim()) ||
      (typeof data.teamName === 'string' && data.teamName.trim()) ||
      doc.id;
    return { teamId: doc.id, name };
  });
}
