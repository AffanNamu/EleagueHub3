// lib/highlights/highlightsRepository.ts
//
// Mirrors lib/features/highlights/data/highlights_repository_firebase.dart
// field-for-field and behavior-for-behavior. Firestore structure
// (independent of leagues/{leagueId}/matches, per spec):
// matches/{matchId}/highlights/{highlightId}

import {
  collection,
  doc,
  getDoc,
  getDocFromServer,
  getDocs,
  setDoc,
  deleteDoc,
  onSnapshot,
  orderBy,
  query,
  where,
  limit,
  serverTimestamp,
  Unsubscribe,
} from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { FixtureMatch } from '@/lib/models/leagueDetails';
import {
  MatchHighlight,
  parseMatchHighlight,
  HIGHLIGHT_STATUS_UPLOADING,
  HIGHLIGHT_STATUS_PROCESSING,
  isHighlightUploading,
} from './types';

export class HighlightsUserFriendlyError extends Error {}

function requireUid(): string {
  const uid = auth.currentUser?.uid?.trim() || '';
  if (!uid) throw new HighlightsUserFriendlyError('Please sign in and try again.');
  return uid;
}

function highlightsCol(matchId: string) {
  const mid = matchId.trim();
  if (!mid) throw new HighlightsUserFriendlyError('Invalid match id.');
  return collection(db, 'matches', mid, 'highlights');
}

/** Watches highlights for a match (Firestore onSnapshot, newest first). */
export function watchHighlightsForMatch(
  matchId: string,
  onData: (highlights: MatchHighlight[]) => void,
): Unsubscribe {
  const mid = matchId.trim();
  if (!mid) {
    onData([]);
    return () => {};
  }

  const q = query(highlightsCol(mid), orderBy('createdAt', 'desc'));
  return onSnapshot(q, (snap) => {
    onData(snap.docs.map(parseMatchHighlight));
  });
}

function isMatchFinishedForHighlights(match: FixtureMatch): boolean {
  return match.status === 'completed' || match.status === 'played' || !!match.isPlayed;
}

/**
 * Determines (and returns) which team a highlight upload should be
 * attributed to, mirroring requireUploadTeamIdOrThrow exactly:
 * - match must be finished
 * - team-member path: membership.teamId must be home/away
 * - league-owner path: caller supplies preferredTeamId (validated against
 *   the match's actual home/away teams)
 */
export async function requireUploadTeamIdOrThrow(params: {
  match: FixtureMatch;
  isLeagueOwner?: boolean;
  preferredTeamId?: string;
}): Promise<string> {
  const { match, isLeagueOwner = false, preferredTeamId } = params;
  const uid = requireUid();

  if (!isMatchFinishedForHighlights(match)) {
    throw new HighlightsUserFriendlyError('Highlights can only be uploaded after the match is finished.');
  }

  const homeId = match.homeTeamId.trim();
  const awayId = match.awayTeamId.trim();

  const membershipSnap = await getDocFromServer(doc(db, 'leagues', match.leagueId, 'memberships', uid)).catch(
    () => null,
  );
  const memberTeamId = (membershipSnap?.exists() ? (membershipSnap.data()?.teamId as string | undefined) : '') || '';
  const trimmedMemberTeamId = memberTeamId.trim();

  if (trimmedMemberTeamId && (trimmedMemberTeamId === homeId || trimmedMemberTeamId === awayId)) {
    return trimmedMemberTeamId;
  }

  if (isLeagueOwner) {
    const chosen = (preferredTeamId || '').trim();
    if (!chosen) {
      throw new HighlightsUserFriendlyError('Choose which team this highlight belongs to.');
    }
    if (chosen !== homeId && chosen !== awayId) {
      throw new HighlightsUserFriendlyError('Selected team did not play in this match.');
    }
    return chosen;
  }

  if (!membershipSnap?.exists()) {
    throw new HighlightsUserFriendlyError('You must be a league member to upload highlights.');
  }

  if (!trimmedMemberTeamId) {
    throw new HighlightsUserFriendlyError(
      'Your account is not assigned to a team in this league. Ask the organizer to assign your membership to the home or away team.',
    );
  }

  throw new HighlightsUserFriendlyError('Only home/away team members can upload highlights for this match.');
}

/** Returns the existing highlight (if any) for a team in this match. */
export async function fetchExistingHighlightForTeam(matchId: string, teamId: string): Promise<MatchHighlight | null> {
  const mid = matchId.trim();
  const tid = teamId.trim();
  if (!mid || !tid) return null;

  const snap = await getDocs(query(highlightsCol(mid), where('teamId', '==', tid), limit(1)));
  if (snap.empty) return null;
  return parseMatchHighlight(snap.docs[0]);
}

/**
 * Creates (or resumes) an optimistic UPLOADING highlight document BEFORE
 * the actual Cloudinary upload, mirroring getOrCreateUploadingHighlight.
 */
export async function getOrCreateUploadingHighlight(params: {
  match: FixtureMatch;
  isLeagueOwner?: boolean;
  preferredTeamId?: string;
}): Promise<{ highlightId: string; teamId: string; cloudFolder: string }> {
  const { match } = params;
  const uid = requireUid();
  const teamId = await requireUploadTeamIdOrThrow(params);

  const existing = await fetchExistingHighlightForTeam(match.id, teamId);
  const cloudFolder = `match_highlights/${match.leagueId}/${match.id}/${teamId}`;

  if (existing) {
    if (existing.uploadedBy.trim() && existing.uploadedBy.trim() !== uid) {
      throw new HighlightsUserFriendlyError(
        'A teammate already started uploading this highlight. Please wait or ask them to finish.',
      );
    }

    const hasUrl = existing.secureUrl.trim().length > 0;
    if (hasUrl && !isHighlightUploading(existing)) {
      throw new HighlightsUserFriendlyError('Your team has already uploaded a highlight for this match.');
    }

    await setDoc(
      doc(highlightsCol(match.id), existing.id),
      {
        matchId: match.id,
        leagueId: match.leagueId,
        teamId,
        uploadedBy: uid,
        cloudinaryPublicId: `${cloudFolder}/${existing.id}`,
        status: HIGHLIGHT_STATUS_UPLOADING,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );

    return { highlightId: existing.id, teamId, cloudFolder };
  }

  const ref = doc(highlightsCol(match.id));
  const highlightId = ref.id;

  await setDoc(
    ref,
    {
      id: highlightId,
      matchId: match.id,
      leagueId: match.leagueId,
      teamId,
      uploadedBy: uid,
      cloudinaryPublicId: `${cloudFolder}/${highlightId}`,
      secureUrl: '',
      thumbnailUrl: '',
      duration: 0,
      size: 0,
      format: '',
      status: HIGHLIGHT_STATUS_UPLOADING,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );

  return { highlightId, teamId, cloudFolder };
}

/** Updates the doc after a Cloudinary upload succeeds. Moves to PROCESSING (not APPROVED) for moderation. */
export async function markUploadSucceeded(params: {
  matchId: string;
  highlightId: string;
  cloudinaryPublicId: string;
  secureUrl: string;
  thumbnailUrl: string;
  duration: number;
  size: number;
  format: string;
}): Promise<void> {
  requireUid();
  const { matchId, highlightId, ...rest } = params;

  await setDoc(
    doc(highlightsCol(matchId), highlightId),
    {
      ...rest,
      status: HIGHLIGHT_STATUS_PROCESSING,
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

export async function markUploadFailed(matchId: string, highlightId: string): Promise<void> {
  requireUid();
  await setDoc(
    doc(highlightsCol(matchId), highlightId),
    {
      secureUrl: '',
      thumbnailUrl: '',
      status: HIGHLIGHT_STATUS_UPLOADING,
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

export async function deleteHighlight(matchId: string, highlightId: string): Promise<void> {
  requireUid();
  await deleteDoc(doc(highlightsCol(matchId), highlightId));
}
