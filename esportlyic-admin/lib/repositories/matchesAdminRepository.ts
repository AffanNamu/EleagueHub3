// lib/repositories/matchesAdminRepository.ts
//
// Server-only repository for match correction. correctFixtureScore()
// ports AdminService.updateScoreByDocId's shape (direct score/status
// write) plus increments `version` — FixtureMatch carries an explicit
// optimistic-concurrency version field that copyWith does NOT
// auto-increment in the Dart source, meaning callers are expected to
// bump it themselves; this does that on every admin correction.
//
// createPointAdjustment() ports AdminService.createPointAdjustment
// exactly: an immutable, transactional write to
// leagues/{id}/pointAdjustments/{autoId} plus an update to the team's
// aggregate adjustment field — this is the ONE place in the whole
// mobile codebase that already had a real audit-trail pattern, and it's
// the reason a top-level audit_logs collection made sense to build.
// Both writes happen here (leagues/{id}/pointAdjustments AND our own
// audit_logs), so the record exists in both the mobile-app-readable
// collection and this workspace's unified log.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import { isConfirmedStatus } from '@/lib/models/match';
import type { FixtureMatch, KnockoutMatch, PointAdjustment } from '@/types/match';

function toFixtureMatch(id: string, leagueId: string, data: FirebaseFirestore.DocumentData): FixtureMatch {
  return {
    id,
    leagueId,
    groupId: data.groupId ?? null,
    roundNumber: typeof data.roundNumber === 'number' ? data.roundNumber : 0,
    homeTeamId: data.homeTeamId ?? '',
    awayTeamId: data.awayTeamId ?? '',
    homeScore: typeof data.homeScore === 'number' ? data.homeScore : null,
    awayScore: typeof data.awayScore === 'number' ? data.awayScore : null,
    status: data.status ?? 'scheduled',
    sortIndex: typeof data.sortIndex === 'number' ? data.sortIndex : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
    version: typeof data.version === 'number' ? data.version : 0,
  };
}

function toKnockoutMatch(id: string, leagueId: string, data: FirebaseFirestore.DocumentData): KnockoutMatch {
  return {
    id,
    leagueId,
    roundName: data.roundName ?? '',
    homeTeamId: data.homeTeamId ?? null,
    awayTeamId: data.awayTeamId ?? null,
    homeScore: typeof data.homeScore === 'number' ? data.homeScore : null,
    awayScore: typeof data.awayScore === 'number' ? data.awayScore : null,
    status: data.status ?? 'scheduled',
    tiebreakWinnerTeamId: data.tiebreakWinnerTeamId ?? null,
    nextMatchId: data.nextMatchId ?? null,
    loserGoesToMatchId: data.loserGoesToMatchId ?? null,
    isSecondLeg: data.isSecondLeg === true,
  };
}

function toPointAdjustment(id: string, data: FirebaseFirestore.DocumentData): PointAdjustment {
  return {
    id,
    leagueId: data.leagueId ?? '',
    teamId: data.teamId ?? '',
    type: (data.type as PointAdjustment['type']) ?? 'ADDITION',
    points: typeof data.points === 'number' ? data.points : 0,
    reason: data.reason ?? '',
    adjustedBy: data.adjustedBy ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
  };
}

export async function listFixtureMatches(leagueId: string): Promise<FixtureMatch[]> {
  const snap = await adminDb
    .collection('leagues')
    .doc(leagueId)
    .collection('matches')
    .orderBy('sortIndex', 'asc')
    .get();
  return snap.docs.map((doc) => toFixtureMatch(doc.id, leagueId, doc.data()));
}

export async function listKnockoutMatches(leagueId: string): Promise<KnockoutMatch[]> {
  const snap = await adminDb.collection('leagues').doc(leagueId).collection('knockout').get();
  return snap.docs.map((doc) => toKnockoutMatch(doc.id, leagueId, doc.data()));
}

export async function listPointAdjustments(leagueId: string): Promise<PointAdjustment[]> {
  const snap = await adminDb
    .collection('leagues')
    .doc(leagueId)
    .collection('pointAdjustments')
    .orderBy('createdAtMs', 'desc')
    .limit(50)
    .get();
  return snap.docs.map((doc) => toPointAdjustment(doc.id, doc.data()));
}

export class MatchCorrectionError extends Error {}

export async function correctFixtureScore(params: {
  leagueId: string;
  matchId: string;
  homeScore: number;
  awayScore: number;
  status: 'scheduled' | 'completed' | 'played';
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  if (!isConfirmedStatus(params.status)) {
    throw new MatchCorrectionError('Invalid status.');
  }

  const ref = adminDb.collection('leagues').doc(params.leagueId).collection('matches').doc(params.matchId);
  const snap = await ref.get();
  if (!snap.exists) throw new MatchCorrectionError('Match not found.');

  const currentVersion = typeof snap.data()?.version === 'number' ? snap.data()!.version : 0;
  const nowMs = Date.now();

  await ref.update({
    homeScore: params.homeScore,
    awayScore: params.awayScore,
    status: params.status,
    updatedAtMs: nowMs,
    version: currentVersion + 1,
  });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'match.score.correct',
    targetType: 'fixture_match',
    targetId: `${params.leagueId}/${params.matchId}`,
    summary: `Corrected score to ${params.homeScore}–${params.awayScore} (${params.status}) on match ${params.matchId}`,
  });
}

export async function correctKnockoutScore(params: {
  leagueId: string;
  matchId: string;
  homeScore: number;
  awayScore: number;
  status: 'scheduled' | 'completed' | 'played';
  tiebreakWinnerTeamId: string | null;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  if (!isConfirmedStatus(params.status)) {
    throw new MatchCorrectionError('Invalid status.');
  }

  const ref = adminDb.collection('leagues').doc(params.leagueId).collection('knockout').doc(params.matchId);
  const snap = await ref.get();
  if (!snap.exists) throw new MatchCorrectionError('Knockout match not found.');

  await ref.update({
    homeScore: params.homeScore,
    awayScore: params.awayScore,
    status: params.status,
    tiebreakWinnerTeamId: params.tiebreakWinnerTeamId,
  });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'match.knockout_score.correct',
    targetType: 'knockout_match',
    targetId: `${params.leagueId}/${params.matchId}`,
    summary: `Corrected knockout score to ${params.homeScore}–${params.awayScore} (${params.status}) on match ${params.matchId}`,
  });
}

export async function createPointAdjustment(params: {
  leagueId: string;
  teamId: string;
  type: 'ADDITION' | 'DEDUCTION';
  points: number;
  reason: string;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  if (params.points <= 0 || params.points > 1000) {
    throw new MatchCorrectionError('Points must be between 1 and 1000.');
  }
  if (!params.reason.trim()) {
    throw new MatchCorrectionError('A reason is required.');
  }

  const nowMs = Date.now();
  const adjustmentRef = adminDb.collection('leagues').doc(params.leagueId).collection('pointAdjustments').doc();
  const teamRef = adminDb.collection('leagues').doc(params.leagueId).collection('teams').doc(params.teamId);

  const delta = params.type === 'ADDITION' ? params.points : -params.points;

  await adminDb.runTransaction(async (transaction) => {
    const teamSnap = await transaction.get(teamRef);
    if (!teamSnap.exists) {
      throw new MatchCorrectionError('Team not found.');
    }

    const currentAdjustment = typeof teamSnap.data()?.adminAdjustment === 'number' ? teamSnap.data()!.adminAdjustment : 0;

    transaction.set(adjustmentRef, {
      id: adjustmentRef.id,
      leagueId: params.leagueId,
      teamId: params.teamId,
      type: params.type,
      points: params.points,
      reason: params.reason.trim(),
      adjustedBy: params.actorUid,
      createdAt: new Date(),
      createdAtMs: nowMs,
    });

    transaction.update(teamRef, {
      adminAdjustment: currentAdjustment + delta,
    });
  });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: `match.point_adjustment.${params.type.toLowerCase()}`,
    targetType: 'league_team',
    targetId: `${params.leagueId}/${params.teamId}`,
    summary: `${params.type === 'ADDITION' ? 'Added' : 'Deducted'} ${params.points} point(s) for team ${params.teamId}: ${params.reason.trim()}`,
  });
}
