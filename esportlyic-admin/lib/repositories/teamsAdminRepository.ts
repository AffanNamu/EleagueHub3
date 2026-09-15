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
import type { LeagueMembership, LeagueTeam, RosterMember, TeamWithRoster } from '@/types/team';

const LEAGUES_COLLECTION = 'leagues';

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
