// web_client/lib/leagues/lateJoinRepository.ts
//
// PHASE D: Firestore I/O for safe late-participant join -- mirrors
// LocalLeaguesRepository.previewLateJoin()/commitLateJoin() on the Flutter
// side (see lateJoinPlanner.ts / late_join_planner.dart for the full
// rationale). A late join never calls the full teams/matches rewrite
// paths: it only ever adds brand-new documents -- the new fixtures via a
// plain additive writeBatch (touches nothing else), and the new team via
// a single additive setDoc. previewLateJoin is read-only. commitLateJoin
// re-fetches and re-plans from the CURRENT server state immediately
// before writing, so a result entered while the preview was on screen is
// never silently overwritten.

import { collection, doc, getDocs, setDoc, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { FixtureMatch, Team } from '@/lib/models/leagueDetails';
import { LeagueFormat } from '@/lib/models/leagueFormat';
import {
  planLateJoin,
  supportsLateJoinFormat,
  LateJoinPreview,
  LateJoinUnsupportedFormatError,
} from '@/lib/algorithms/lateJoinPlanner';

/** Placeholder id used only inside previewLateJoin -- the real team doesn't
 *  exist yet at preview time (it's created in commitLateJoin, which then
 *  re-plans with the team's REAL id). Only the counts in the returned
 *  LateJoinPreview are meaningful to show the organizer; the placeholder
 *  never reaches Firestore. */
const PREVIEW_PLACEHOLDER_TEAM_ID = '__late_join_preview__';

async function fetchExistingTeamIds(leagueId: string): Promise<string[]> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'teams'));
  return snap.docs.map((d) => d.id);
}

async function fetchExistingMatches(leagueId: string): Promise<FixtureMatch[]> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'matches'));
  return snap.docs.map((d) => {
    const data = d.data() as Partial<FixtureMatch>;
    const id = (data.id && String(data.id).trim()) || d.id;
    return { ...data, id } as FixtureMatch;
  });
}

/**
 * Read-only: computes what adding a new team to `leagueId` would do,
 * without writing anything or creating the team. Throws
 * LateJoinUnsupportedFormatError if the league's format doesn't support
 * late joining.
 */
export async function previewLateJoin({
  leagueId,
  format,
  doubleRoundRobin,
}: {
  leagueId: string;
  format: LeagueFormat;
  doubleRoundRobin: boolean;
}): Promise<LateJoinPreview> {
  const [existingTeamIds, existingMatches] = await Promise.all([
    fetchExistingTeamIds(leagueId),
    fetchExistingMatches(leagueId),
  ]);

  return planLateJoin({
    format,
    leagueId,
    existingMatches,
    existingTeamIds,
    newTeamId: PREVIEW_PLACEHOLDER_TEAM_ID,
    doubleRoundRobin,
  });
}

/**
 * Creates `newTeamName` as a new external (unclaimed) team -- a single
 * additive doc write, same shape as a manually-added team elsewhere in
 * this app -- and then re-plans from the CURRENT server state (never
 * trusts a preview the caller computed earlier) and writes only the new
 * fixtures. No existing match is ever touched. Throws
 * LateJoinUnsupportedFormatError (no team is created) if the league's
 * format doesn't support late joining.
 */
export async function commitLateJoin({
  leagueId,
  format,
  doubleRoundRobin,
  newTeamName,
  teamImageUrl = '',
}: {
  leagueId: string;
  format: LeagueFormat;
  doubleRoundRobin: boolean;
  newTeamName: string;
  teamImageUrl?: string;
}): Promise<{ team: Team; preview: LateJoinPreview }> {
  if (!supportsLateJoinFormat(format)) {
    throw new LateJoinUnsupportedFormatError(format);
  }

  const trimmedName = newTeamName.trim();
  if (!trimmedName) {
    throw new Error('Please enter a team name.');
  }

  const [existingTeamIds, existingMatches] = await Promise.all([
    fetchExistingTeamIds(leagueId),
    fetchExistingMatches(leagueId),
  ]);

  const teamRef = doc(collection(db, 'leagues', leagueId, 'teams'));
  const now = Date.now();
  const team: Team = {
    id: teamRef.id,
    leagueId,
    name: trimmedName,
    ownerId: '',
    teamImageUrl,
    groupId: null,
    basePoints: 0,
    adminAdjustment: 0,
    finalPoints: 0,
    goalDifference: 0,
    goalsFor: 0,
    participantType: 'external',
    claimStatus: 'not_claimed',
    updatedAtMs: now,
  };
  await setDoc(teamRef, team);

  const plan = planLateJoin({
    format,
    leagueId,
    existingMatches,
    existingTeamIds,
    newTeamId: team.id,
    doubleRoundRobin,
  });

  const matchesRef = collection(db, 'leagues', leagueId, 'matches');
  const chunkSize = 400;
  for (let i = 0; i < plan.newFixtures.length; i += chunkSize) {
    const batch = writeBatch(db);
    for (const m of plan.newFixtures.slice(i, i + chunkSize)) {
      batch.set(doc(matchesRef, m.id), m, { merge: true });
    }
    await batch.commit();
  }

  return { team, preview: plan };
}
