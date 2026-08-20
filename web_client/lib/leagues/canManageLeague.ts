// lib/leagues/canManageLeague.ts
//
// Determines whether `uid` can manage (pin/delete-any) chat messages in
// `leagueId`. Mirrors the exact ownership check in RoleGuard.tsx:
//   1) league.organizerUid / organizerUserId matches uid, OR
//   2) a doc in leagues/{id}/memberships/{uid} with role === 0 (organizer)
// Kept as a standalone function (RoleGuard is a wrapping component, not
// something you can call for a plain boolean) so chat pages can use the
// same authoritative check without duplicating or drifting from it.

import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { leagueFromRemoteMap, isOwnerForViewer } from '@/lib/models/league';

export async function checkCanManageLeague(leagueId: string, uid: string): Promise<boolean> {
  if (!leagueId || !uid) return false;

  try {
    const leagueRef = doc(db, 'leagues', leagueId);
    const membershipRef = doc(db, 'leagues', leagueId, 'memberships', uid);

    const [leagueSnap, membershipSnap] = await Promise.all([
      getDoc(leagueRef),
      getDoc(membershipRef),
    ]);

    if (!leagueSnap.exists()) return false;

    const league = leagueFromRemoteMap({ ...leagueSnap.data(), id: leagueSnap.id });
    const isOwnerByLeague = isOwnerForViewer(league, uid);
    const isOwnerByMembership = membershipSnap.exists() && membershipSnap.data()?.role === 0;

    return isOwnerByLeague || isOwnerByMembership;
  } catch (err) {
    console.error('[canManageLeague] check failed:', err);
    return false;
  }
}
