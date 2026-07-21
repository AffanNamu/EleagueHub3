import { collection, doc, getDoc, getDocs, query, orderBy, limit } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { LeagueData, leagueFromRemoteMap } from '@/lib/models/league';
import { Team, FixtureMatch, KnockoutMatch, LeagueAnnouncement } from '@/lib/models/leagueDetails';

export interface FullLeagueDetails {
  league: LeagueData;
  isOwner: boolean;
  isJoined: boolean;
  teams: Record<string, Team>;
  fixtures: FixtureMatch[];
  knockouts: KnockoutMatch[];
  announcements: LeagueAnnouncement[];
  partialErrors: string[];
}

// Thrown only when the league document itself genuinely doesn't exist,
// or when the caller has no permission to read it at all. This lets the
// UI distinguish "really not found / no access" from "one subcollection
// read failed" instead of collapsing every failure into one message.
export class LeagueFetchError extends Error {
  constructor(message: string, public readonly cause?: unknown) {
    super(message);
    this.name = 'LeagueFetchError';
  }
}

export async function fetchFullLeagueDetails(leagueId: string, authUid: string): Promise<FullLeagueDetails> {
  if (!leagueId) {
    throw new LeagueFetchError('No league id was provided.');
  }

  // ── Step 1: fetch the league doc on its own ──────────────────────────────
  // If THIS fails, it really is "not found / no access." We do not want a
  // failure in some unrelated subcollection masquerading as this.
  const leagueRef = doc(db, 'leagues', leagueId);
  let leagueSnap;
  try {
    leagueSnap = await getDoc(leagueRef);
  } catch (error) {
    console.error('[fetchFullLeagueDetails] Failed to read league doc:', error);
    const msg = error instanceof Error ? error.message : 'Unknown error';
    throw new LeagueFetchError(`Could not read league: ${msg}`, error);
  }

  if (!leagueSnap.exists()) {
    throw new LeagueFetchError('This league does not exist or has been deleted.');
  }

  const league = leagueFromRemoteMap({ ...leagueSnap.data(), id: leagueSnap.id });

  // ── Step 2: fetch everything else, but don't let one failure nuke the rest ──
  const teamsRef = collection(db, 'leagues', leagueId, 'teams');
  const matchesRef = collection(db, 'leagues', leagueId, 'matches');
  const knockoutsRef = collection(db, 'leagues', leagueId, 'knockout_matches');
  const announcementsRef = collection(db, 'leagues', leagueId, 'announcements');
  const membershipRef = doc(db, 'leagues', leagueId, 'memberships', authUid);

  const [
    teamsResult,
    matchesResult,
    knockoutsResult,
    announcementsResult,
    membershipResult,
  ] = await Promise.allSettled([
    getDocs(teamsRef),
    getDocs(matchesRef),
    getDocs(knockoutsRef),
    getDocs(query(announcementsRef, orderBy('createdAtMs', 'desc'), limit(10))),
    getDoc(membershipRef),
  ]);

  const partialErrors: string[] = [];

  const teams: Record<string, Team> = {};
  if (teamsResult.status === 'fulfilled') {
    teamsResult.value.forEach((d) => {
      teams[d.id] = { ...d.data(), id: d.id } as Team;
    });
  } else {
    console.error('[fetchFullLeagueDetails] teams read failed:', teamsResult.reason);
    partialErrors.push(`Teams: ${describeError(teamsResult.reason)}`);
  }

  const fixtures: FixtureMatch[] = [];
  if (matchesResult.status === 'fulfilled') {
    matchesResult.value.forEach((d) => fixtures.push({ ...d.data(), id: d.id } as FixtureMatch));
    fixtures.sort((a, b) => {
      if (a.roundNumber !== b.roundNumber) return a.roundNumber - b.roundNumber;
      return a.sortIndex - b.sortIndex;
    });
  } else {
    console.error('[fetchFullLeagueDetails] matches read failed:', matchesResult.reason);
    partialErrors.push(`Fixtures: ${describeError(matchesResult.reason)}`);
  }

  const knockouts: KnockoutMatch[] = [];
  if (knockoutsResult.status === 'fulfilled') {
    knockoutsResult.value.forEach((d) => knockouts.push({ ...d.data(), id: d.id } as KnockoutMatch));
  } else {
    console.error('[fetchFullLeagueDetails] knockouts read failed:', knockoutsResult.reason);
    partialErrors.push(`Knockouts: ${describeError(knockoutsResult.reason)}`);
  }

  const announcements: LeagueAnnouncement[] = [];
  if (announcementsResult.status === 'fulfilled') {
    announcementsResult.value.forEach((d) => announcements.push({ ...d.data(), id: d.id } as LeagueAnnouncement));
  } else {
    console.error('[fetchFullLeagueDetails] announcements read failed:', announcementsResult.reason);
    partialErrors.push(`Announcements: ${describeError(announcementsResult.reason)}`);
  }

  let membershipExists = false;
  let membershipIsOrganizerRole = false;
  if (membershipResult.status === 'fulfilled') {
    membershipExists = membershipResult.value.exists();
    membershipIsOrganizerRole = membershipExists && membershipResult.value.data()?.role === 0;
  } else {
    console.error('[fetchFullLeagueDetails] membership read failed:', membershipResult.reason);
    partialErrors.push(`Membership: ${describeError(membershipResult.reason)}`);
  }

  const isOwnerByLeague = league.organizerUid === authUid || league.organizerUserId === authUid;
  const isOwner = isOwnerByLeague || membershipIsOrganizerRole;
  const isJoined = membershipExists || isOwner;

  if (partialErrors.length > 0) {
    console.warn('[fetchFullLeagueDetails] Loaded league with partial errors:', partialErrors);
  }

  return {
    league,
    isOwner,
    isJoined,
    teams,
    fixtures,
    knockouts,
    announcements,
    partialErrors,
  };
}

function describeError(reason: unknown): string {
  if (reason instanceof Error) return reason.message;
  return String(reason);
}
