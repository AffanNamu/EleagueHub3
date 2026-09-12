// lib/leagues/competitionRulesRepository.ts
//
// Mirrors the "Competition Rules" section of
// lib/features/leagues/data/leagues_repository_firebase.dart
// (getCompetitionRules / watchCompetitionRules / saveCompetitionRules).
//
// Stored at leagues/{leagueId}/competitionRules/current, with archived
// versions at leagues/{leagueId}/competitionRules/v{n} once a locked
// version is later edited. Authorization is enforced by Firestore rules
// (canManageLeague() for writes, any signed-in member for reads) — this
// file does not duplicate that check.

import { collection, doc, getDoc, onSnapshot, setDoc, writeBatch } from 'firebase/firestore';
import { useEffect, useState } from 'react';
import { db } from '@/lib/firebase';
import { CompetitionRules, competitionRulesFromMap, competitionRulesToMap } from '@/lib/models/competitionRules';

const CURRENT_DOC_ID = 'current';
const historyDocId = (version: number) => `v${version}`;

function competitionRulesCol(leagueId: string) {
  return collection(db, 'leagues', leagueId.trim(), 'competitionRules');
}

/** Returns the current published rules for a league, or null if the organizer hasn't configured any yet. */
export async function getCompetitionRules(leagueId: string): Promise<CompetitionRules | null> {
  const id = leagueId.trim();
  if (!id) return null;

  const snap = await getDoc(doc(competitionRulesCol(id), CURRENT_DOC_ID));
  if (!snap.exists()) return null;
  const data = snap.data();
  if (!data) return null;
  return competitionRulesFromMap(data, id);
}

/** Live-subscribes to the current published rules for a league. Emits null when nothing is configured yet. */
export function useCompetitionRules(leagueId: string) {
  const [rules, setRules] = useState<CompetitionRules | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const id = leagueId.trim();
    if (!id) {
      const timer = setTimeout(() => {
        setRules(null);
        setLoading(false);
      }, 0);
      return () => clearTimeout(timer);
    }

    const unsub = onSnapshot(
      doc(competitionRulesCol(id), CURRENT_DOC_ID),
      (snap) => {
        if (!snap.exists()) {
          setRules(null);
        } else {
          const data = snap.data();
          setRules(data ? competitionRulesFromMap(data, id) : null);
        }
        setLoading(false);
      },
      (err) => {
        console.warn('[competitionRulesRepository] watch failed:', err);
        setRules(null);
        setLoading(false);
      },
    );
    return () => unsub();
  }, [leagueId]);

  return { rules, loading };
}

/**
 * Creates or updates the competition rules for `rules.leagueId`.
 *
 * Versioning behavior:
 * - No existing doc -> written as version 1.
 * - Existing doc, NOT locked -> overwritten in place, version bumped by 1.
 *   No history entry — organizers can iterate freely before the
 *   competition starts.
 * - Existing doc IS locked -> the current doc is archived first to
 *   competitionRules/v{oldVersion}, then the new content is written as
 *   competitionRules/current with version = oldVersion + 1.
 *
 * `rules.locked` in the input controls the *new* doc's locked state —
 * pass true to publish-and-lock, false to save as an editable draft.
 */
export async function saveCompetitionRules(rules: CompetitionRules, authUid: string): Promise<CompetitionRules> {
  const leagueId = rules.leagueId.trim();
  if (!leagueId) {
    throw new Error("We couldn't save the rules. Please refresh and try again.");
  }

  const col = competitionRulesCol(leagueId);
  const currentRef = doc(col, CURRENT_DOC_ID);

  const existing = await getDoc(currentRef);
  const now = Date.now();
  let nextVersion = 1;

  if (existing.exists()) {
    const existingData = existing.data() ?? {};
    const existingVersion = typeof existingData.version === 'number' ? existingData.version : 1;
    const existingLocked = existingData.locked === true;
    nextVersion = existingVersion + 1;

    if (existingLocked) {
      const historyRef = doc(col, historyDocId(existingVersion));
      const toWrite: CompetitionRules = { ...rules, leagueId, version: nextVersion, updatedAtMs: now, updatedBy: authUid };

      const batch = writeBatch(db);
      batch.set(historyRef, existingData);
      batch.set(currentRef, competitionRulesToMap(toWrite));
      await batch.commit();

      return toWrite;
    }
  }

  const toWrite: CompetitionRules = { ...rules, leagueId, version: nextVersion, updatedAtMs: now, updatedBy: authUid };
  await setDoc(currentRef, competitionRulesToMap(toWrite));
  return toWrite;
}
