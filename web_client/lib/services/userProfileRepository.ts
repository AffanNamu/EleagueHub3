import { doc, getDoc, collection, query, where, orderBy, limit, getDocs, documentId } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface ResolvedUserProfile {
  userId: string;
  teamName: string;
  photoUrl: string;
}

function stringFromAny(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

/**
 * Mirrors UserProfile.deriveShareIdFromUid from user_profile.dart:
 *   clean = uid with all non-alphanumeric characters stripped
 *   base  = first 8 chars of clean (or right-padded with 'X' if shorter)
 *   shareId = "eS" + base
 */
export function deriveShareIdFromUid(uid: string): string {
  const clean = uid.replace(/[^A-Za-z0-9]/g, '').trim();
  if (!clean) return '';
  const base = clean.length >= 8 ? clean.substring(0, 8) : clean.padEnd(8, 'X');
  return `eS${base}`;
}

/**
 * Reads a user profile directly by their Firebase uid, mirroring the
 * "users/{uid}" document written by the Flutter app (see profile_screen.dart:
 * teamName, photoUrl / profileImageUrl / teamImageUrl fields).
 */
export async function fetchUserProfileByUserId(
  userId: string,
): Promise<ResolvedUserProfile | null> {
  const uid = userId.trim();
  if (!uid) return null;

  const snap = await getDoc(doc(db, 'users', uid));
  if (!snap.exists()) return null;

  const data = snap.data();
  const teamName = stringFromAny(data.teamName);
  if (!teamName) return null;

  const photoUrl =
    stringFromAny(data.photoUrl) ||
    stringFromAny(data.profileImageUrl) ||
    stringFromAny(data.teamImageUrl);

  return { userId: uid, teamName, photoUrl };
}

/**
 * Resolves a short shareId (e.g. "eSV5C88TX") back to a real user by
 * range-querying document IDs that start with the same 8-char uid prefix
 * the shareId was derived from.
 */
async function resolveByShareId(shareId: string): Promise<ResolvedUserProfile | null> {
  const trimmed = shareId.trim();
  if (!trimmed.startsWith('eS') || trimmed.length < 4) return null;

  const prefix = trimmed.substring(2, 10);
  if (!prefix) return null;

  const usersRef = collection(db, 'users');
  const q = query(
    usersRef,
    orderBy(documentId()),
    where(documentId(), '>=', prefix),
    where(documentId(), '<', prefix + '\uf8ff'),
    limit(5),
  );

  const snap = await getDocs(q);
  for (const d of snap.docs) {
    if (deriveShareIdFromUid(d.id) === trimmed) {
      const data = d.data();
      const teamName = stringFromAny(data.teamName);
      if (!teamName) continue;
      const photoUrl =
        stringFromAny(data.photoUrl) ||
        stringFromAny(data.profileImageUrl) ||
        stringFromAny(data.teamImageUrl);
      return { userId: d.id, teamName, photoUrl };
    }
  }

  return null;
}

/**
 * Resolves a team participant from raw admin input. Accepts either:
 *   - a full Firebase uid, or
 *   - a short shareId in the "eSxxxxxxxx" format shown in the Flutter app.
 */
export async function resolveTeamParticipant(
  input: string,
): Promise<ResolvedUserProfile | null> {
  const trimmed = input.trim();
  if (!trimmed) return null;

  if (trimmed.startsWith('eS') && trimmed.length <= 12) {
    return resolveByShareId(trimmed);
  }

  if (trimmed.length >= 20) {
    return fetchUserProfileByUserId(trimmed);
  }

  return null;
}
