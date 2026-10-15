// web_client/lib/leagues/replaceParticipantRepository.ts
//
// Firestore I/O for safe participant replacement -- mirrors
// LocalLeaguesRepository.previewReplaceParticipant()/commitReplaceParticipant()
// on the Flutter side (see replaceParticipantPlanner.ts /
// replace_participant_planner.dart for the full rationale). Only ever
// updates the home/away team-id field of an already-existing match
// document via the same additive upsert primitives used elsewhere
// (writeBatch set with merge:true, and knockoutRepository's own
// saveKnockoutMatches, which -- unlike the Dart port -- is a plain upsert
// with no diffing/pruning, so writing just the changed subset is safe
// here without any extra merge-back step).

import { collection, doc, getDocs, setDoc, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { FixtureMatch, KnockoutMatch, Team } from '@/lib/models/leagueDetails';
import { planReplaceParticipant, ReplaceParticipantPreview } from '@/lib/algorithms/replaceParticipantPlanner';
import { saveKnockoutMatches } from './knockoutRepository';

/** Creates a new external (unclaimed) team -- same shape as
 *  lateJoinRepository.ts's own team creation, kept as its own small copy
 *  here rather than extracted/shared, so this change doesn't touch that
 *  already-shipped file. */
export async function createReplacementTeam({
  leagueId,
  name,
  teamImageUrl = '',
}: {
  leagueId: string;
  name: string;
  teamImageUrl?: string;
}): Promise<Team> {
  const trimmedName = name.trim();
  if (!trimmedName) {
    throw new Error('Please enter a team name.');
  }

  const teamRef = doc(collection(db, 'leagues', leagueId, 'teams'));
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
    updatedAtMs: Date.now(),
  };
  await setDoc(teamRef, team);
  return team;
}

async function fetchExistingTeams(leagueId: string): Promise<Team[]> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'teams'));
  return snap.docs.map((d) => ({ ...(d.data() as object), id: d.id } as Team));
}

async function fetchExistingFixtures(leagueId: string): Promise<FixtureMatch[]> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'matches'));
  return snap.docs.map((d) => {
    const data = d.data() as Partial<FixtureMatch>;
    const id = (data.id && String(data.id).trim()) || d.id;
    return { ...data, id } as FixtureMatch;
  });
}

async function fetchExistingKnockouts(leagueId: string): Promise<KnockoutMatch[]> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'knockout'));
  return snap.docs.map((d) => {
    const data = d.data() as Partial<KnockoutMatch>;
    const id = (data.id && String(data.id).trim()) || d.id;
    return { ...data, id } as KnockoutMatch;
  });
}

/** Teams with zero existing appearances in this league's matches/knockout
 *  collections -- the organizer-facing "eligible replacement" list. */
export async function getEligibleReplacementTeams({
  leagueId,
  excludeTeamId,
}: {
  leagueId: string;
  excludeTeamId: string;
}): Promise<Team[]> {
  const [teams, matches, knockouts] = await Promise.all([
    fetchExistingTeams(leagueId),
    fetchExistingFixtures(leagueId),
    fetchExistingKnockouts(leagueId),
  ]);

  const playingTeamIds = new Set<string>();
  for (const m of matches) {
    playingTeamIds.add(m.homeTeamId);
    playingTeamIds.add(m.awayTeamId);
  }
  for (const m of knockouts) {
    if (m.homeTeamId) playingTeamIds.add(m.homeTeamId);
    if (m.awayTeamId) playingTeamIds.add(m.awayTeamId);
  }

  return teams.filter((t) => t.id !== excludeTeamId.trim() && !playingTeamIds.has(t.id));
}

/** Read-only: computes what replacing `oldTeamId` with `newTeamId` would
 *  do, without writing anything. Both teams must already exist in the
 *  league. Throws ReplaceParticipantBlockedError if unsafe. */
export async function previewReplaceParticipant({
  leagueId,
  oldTeamId,
  newTeamId,
}: {
  leagueId: string;
  oldTeamId: string;
  newTeamId: string;
}): Promise<ReplaceParticipantPreview> {
  const [existingFixtureMatches, existingKnockoutMatches] = await Promise.all([
    fetchExistingFixtures(leagueId),
    fetchExistingKnockouts(leagueId),
  ]);

  return planReplaceParticipant({ oldTeamId, newTeamId, existingFixtureMatches, existingKnockoutMatches });
}

/** Re-plans from the CURRENT server state (never trusts a preview the
 *  caller computed earlier) and writes only the eligible matches.
 *  Completed/finished matches are never written. Also records who
 *  performed the replacement and when. */
export async function commitReplaceParticipant({
  leagueId,
  oldTeamId,
  newTeamId,
  performedBy,
}: {
  leagueId: string;
  oldTeamId: string;
  newTeamId: string;
  performedBy: string;
}): Promise<ReplaceParticipantPreview> {
  const [existingFixtureMatches, existingKnockoutMatches] = await Promise.all([
    fetchExistingFixtures(leagueId),
    fetchExistingKnockouts(leagueId),
  ]);

  const plan = planReplaceParticipant({ oldTeamId, newTeamId, existingFixtureMatches, existingKnockoutMatches });

  if (plan.fixtureMatchesToUpdate.length > 0) {
    const matchesRef = collection(db, 'leagues', leagueId, 'matches');
    const chunkSize = 400;
    for (let i = 0; i < plan.fixtureMatchesToUpdate.length; i += chunkSize) {
      const batch = writeBatch(db);
      for (const m of plan.fixtureMatchesToUpdate.slice(i, i + chunkSize)) {
        batch.set(doc(matchesRef, m.id), m, { merge: true });
      }
      await batch.commit();
    }
  }

  if (plan.knockoutMatchesToUpdate.length > 0) {
    // knockoutRepository's saveKnockoutMatches is a plain upsert (no
    // diffing/pruning against the rest of the bracket), so writing just
    // the changed subset is safe.
    await saveKnockoutMatches(leagueId, plan.knockoutMatchesToUpdate);
  }

  const recordRef = doc(collection(db, 'leagues', leagueId, 'participant_replacements'));
  await setDoc(recordRef, {
    id: recordRef.id,
    leagueId,
    oldTeamId,
    newTeamId,
    matchesUpdatedCount: plan.fixtureMatchesToUpdate.length + plan.knockoutMatchesToUpdate.length,
    performedBy,
    performedAtMs: Date.now(),
  });

  return plan;
}
