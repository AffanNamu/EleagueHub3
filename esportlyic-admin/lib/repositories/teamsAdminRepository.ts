// lib/repositories/teamsAdminRepository.ts
//
// listTeamsForLeague()/LeagueTeamSummary stays as-is for its existing
// caller (LeagueMatchesSection, which only needs id+name to label
// matches). getTeamsWithRosters() is the new, fuller read used by the
// roster management UI: a team's roster is derived from
// leagues/{leagueId}/memberships (every membership whose teamId points
// at that team), NOT an array field on the team doc itself -- see
// types/team.ts and membership.dart. renameTeam/removeMemberFromTeam/
// deleteTeam are fine-grained admin primitives; the app's own team
// editor (saveTeams in leagues_repository_local.dart) only supports
// replacing every team in a league at once, which is too blunt an
// operation to reuse for a single-team admin fix.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import { getUserSummary } from '@/lib/repositories/usersAdminRepository';
import type { LeagueTeamSummary } from '@/types/match';
import type { LeagueMembership, LeagueTeam, RosterMember, TeamClaim, TeamWithRoster } from '@/types/team';

const LEAGUES_COLLECTION = 'leagues';
const TEAM_CLAIMS_COLLECTION = 'team_claims';

export class TeamAdminError extends Error {}

export async function listTeamsForLeague(leagueId: string): Promise<LeagueTeamSummary[]> {
  const snap = await adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection('teams').get();
  return snap.docs.map((doc) => {
    const data = doc.data();
    const name =
      (typeof data.name === 'string' && data.name.trim()) ||
      (typeof data.teamName === 'string' && data.teamName.trim()) ||
      doc.id;
    return { teamId: doc.id, name };
  });
}

function toTeam(id: string, leagueId: string, data: FirebaseFirestore.DocumentData): LeagueTeam {
  return {
    id,
    leagueId,
    name: (typeof data.name === 'string' && data.name.trim()) || id,
    ownerId: data.ownerId ?? id,
    teamImageUrl: data.teamImageUrl ?? '',
    groupId: typeof data.groupId === 'string' ? data.groupId : null,
    basePoints: typeof data.basePoints === 'number' ? data.basePoints : 0,
    adminAdjustment: typeof data.adminAdjustment === 'number' ? data.adminAdjustment : 0,
    finalPoints: typeof data.finalPoints === 'number' ? data.finalPoints : 0,
    goalDifference: typeof data.goalDifference === 'number' ? data.goalDifference : 0,
    goalsFor: typeof data.goalsFor === 'number' ? data.goalsFor : 0,
    // Absent on every pre-existing team doc -- undefined here reads as
    // 'registered' at every call site (see ParticipantBadge).
    participantType: data.participantType === 'external' ? 'external' : undefined,
    claimStatus: typeof data.claimStatus === 'string' ? (data.claimStatus as LeagueTeam['claimStatus']) : undefined,
    claimedAtMs: typeof data.claimedAtMs === 'number' ? data.claimedAtMs : undefined,
    createdByUserId: typeof data.createdByUserId === 'string' ? data.createdByUserId : undefined,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

function toMembership(id: string, leagueId: string, data: FirebaseFirestore.DocumentData): LeagueMembership {
  return {
    membershipId: id,
    leagueId,
    userId: data.userId ?? id,
    teamId: typeof data.teamId === 'string' ? data.teamId : null,
    role: typeof data.role === 'number' ? data.role : 1,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

export async function listMembershipsForLeague(leagueId: string): Promise<LeagueMembership[]> {
  const snap = await adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection('memberships').get();
  return snap.docs.map((doc) => toMembership(doc.id, leagueId, doc.data()));
}

/**
 * Teams for a league with their roster resolved from memberships, plus
 * an "Unassigned" bucket (memberships with no teamId, excluding role 0
 * organizers who are never on a roster). Display names are resolved via
 * getUserSummary, capped by how many distinct users actually show up in
 * this league's memberships (never unbounded).
 */
export async function getTeamsWithRosters(
  leagueId: string,
): Promise<{ teams: TeamWithRoster[]; unassigned: RosterMember[] }> {
  const [teamsSnap, memberships] = await Promise.all([
    adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection('teams').get(),
    listMembershipsForLeague(leagueId),
  ]);

  const teams = teamsSnap.docs.map((doc) => toTeam(doc.id, leagueId, doc.data()));

  const rosterMembers = memberships.filter((m) => m.role !== 0);
  const uniqueUserIds = Array.from(new Set(rosterMembers.map((m) => m.userId)));
  const summaries = await Promise.all(uniqueUserIds.map((userId) => getUserSummary(userId)));
  const summaryByUserId = new Map(uniqueUserIds.map((userId, i) => [userId, summaries[i]]));

  function toRosterMember(m: LeagueMembership): RosterMember {
    const summary = summaryByUserId.get(m.userId);
    return {
      membershipId: m.membershipId,
      userId: m.userId,
      displayName: summary?.displayName ?? m.userId,
      photoUrl: summary?.photoUrl ?? '',
    };
  }

  const rosterByTeamId = new Map<string, RosterMember[]>();
  const unassigned: RosterMember[] = [];

  for (const m of rosterMembers) {
    if (m.teamId) {
      const list = rosterByTeamId.get(m.teamId) ?? [];
      list.push(toRosterMember(m));
      rosterByTeamId.set(m.teamId, list);
    } else {
      unassigned.push(toRosterMember(m));
    }
  }

  const teamsWithRosters: TeamWithRoster[] = teams.map((team) => ({
    ...team,
    roster: rosterByTeamId.get(team.id) ?? [],
  }));

  return { teams: teamsWithRosters, unassigned };
}

function toTeamClaim(token: string, data: FirebaseFirestore.DocumentData): TeamClaim {
  return {
    token,
    leagueId: typeof data.leagueId === 'string' ? data.leagueId : '',
    teamId: typeof data.teamId === 'string' ? data.teamId : '',
    status: data.status === 'claimed' || data.status === 'revoked' ? data.status : 'pending',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    createdByUserId: typeof data.createdByUserId === 'string' ? data.createdByUserId : '',
    expiresAtMs: typeof data.expiresAtMs === 'number' ? data.expiresAtMs : 0,
    consumedAtMs: typeof data.consumedAtMs === 'number' ? data.consumedAtMs : null,
    consumedByUserId: typeof data.consumedByUserId === 'string' ? data.consumedByUserId : null,
  };
}

/**
 * Every team_claims doc for a league, newest first. A team can have more
 * than one: generating a fresh link supersedes the old one in practice
 * (the team's own claimStatus is what actually gates confirmation) but
 * never touches the old doc, so stale 'pending' tokens are left behind
 * here for the organizer/admin to see and revoke.
 */
export async function getClaimsForLeague(leagueId: string): Promise<TeamClaim[]> {
  const snap = await adminDb.collection(TEAM_CLAIMS_COLLECTION).where('leagueId', '==', leagueId).get();
  const claims = snap.docs.map((doc) => toTeamClaim(doc.id, doc.data()));

  const consumedUserIds = Array.from(
    new Set(claims.filter((c) => c.status === 'claimed' && c.consumedByUserId).map((c) => c.consumedByUserId as string)),
  );
  const summaries = await Promise.all(consumedUserIds.map((userId) => getUserSummary(userId)));
  const nameByUserId = new Map(consumedUserIds.map((userId, i) => [userId, summaries[i]?.displayName]));

  return claims
    .map((c) => ({
      ...c,
      consumedByDisplayName: c.consumedByUserId ? nameByUserId.get(c.consumedByUserId) ?? c.consumedByUserId : undefined,
    }))
    .sort((a, b) => b.createdAtMs - a.createdAtMs);
}

export async function revokeClaim(
  leagueId: string,
  teamId: string,
  token: string,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  const claimRef = adminDb.collection(TEAM_CLAIMS_COLLECTION).doc(token);
  const claimSnap = await claimRef.get();
  if (!claimSnap.exists) throw new TeamAdminError('Claim link not found.');
  const claim = claimSnap.data()!;
  if (claim.leagueId !== leagueId || claim.teamId !== teamId) {
    throw new TeamAdminError('Claim link does not belong to this team.');
  }
  if (claim.status === 'claimed') {
    throw new TeamAdminError('This team has already been claimed; the link cannot be revoked.');
  }
  if (claim.status === 'revoked') {
    throw new TeamAdminError('This claim link is already revoked.');
  }

  // Only reset the team's claimStatus back to 'revoked' when no other
  // pending token remains for it -- a sibling link generated afterward
  // should keep the team showing as pending, not revoked.
  const siblingsSnap = await adminDb.collection(TEAM_CLAIMS_COLLECTION).where('leagueId', '==', leagueId).get();
  const stillPending = siblingsSnap.docs.some(
    (doc) => doc.id !== token && doc.data().teamId === teamId && doc.data().status === 'pending',
  );

  const teamRef = adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection('teams').doc(teamId);
  const batch = adminDb.batch();
  batch.update(claimRef, { status: 'revoked' });
  if (!stillPending) {
    batch.update(teamRef, { claimStatus: 'revoked', updatedAtMs: Date.now() });
  }
  await batch.commit();

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'team.revoke_claim',
    targetType: 'team',
    targetId: `${leagueId}/${teamId}`,
    summary: `Revoked a claim link for team ${teamId} in league ${leagueId}`,
  });
}

export async function renameTeam(
  leagueId: string,
  teamId: string,
  name: string,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  const trimmed = name.trim();
  if (!trimmed) throw new TeamAdminError('Name is required.');
  if (trimmed.length > 60) throw new TeamAdminError('Name must be 60 characters or fewer.');

  const ref = adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection('teams').doc(teamId);
  const snap = await ref.get();
  if (!snap.exists) throw new TeamAdminError('Team not found.');

  await ref.update({ name: trimmed, updatedAtMs: Date.now() });

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'team.rename',
    targetType: 'team',
    targetId: `${leagueId}/${teamId}`,
    summary: `Renamed team ${teamId} in league ${leagueId} to "${trimmed}"`,
  });
}

export async function removeMemberFromTeam(
  leagueId: string,
  membershipId: string,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  const ref = adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection('memberships').doc(membershipId);
  const snap = await ref.get();
  if (!snap.exists) throw new TeamAdminError('Membership not found.');

  await ref.update({ teamId: null, updatedAtMs: Date.now() });

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'team.remove_member',
    targetType: 'team',
    targetId: `${leagueId}/${membershipId}`,
    summary: `Removed ${membershipId} from their team roster in league ${leagueId}`,
  });
}

export async function deleteTeam(
  leagueId: string,
  teamId: string,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  const teamRef = adminDb.collection(LEAGUES_COLLECTION).doc(leagueId).collection('teams').doc(teamId);
  const teamSnap = await teamRef.get();
  if (!teamSnap.exists) throw new TeamAdminError('Team not found.');
  const name = (teamSnap.data()?.name as string) || teamId;

  const membershipsSnap = await adminDb
    .collection(LEAGUES_COLLECTION)
    .doc(leagueId)
    .collection('memberships')
    .where('teamId', '==', teamId)
    .get();

  const batch = adminDb.batch();
  batch.delete(teamRef);
  const nowMs = Date.now();
  for (const doc of membershipsSnap.docs) {
    batch.update(doc.ref, { teamId: null, updatedAtMs: nowMs });
  }
  await batch.commit();

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'team.delete',
    targetType: 'team',
    targetId: `${leagueId}/${teamId}`,
    summary: `Deleted team "${name}" from league ${leagueId} and released ${membershipsSnap.size} roster member(s)`,
  });
}
