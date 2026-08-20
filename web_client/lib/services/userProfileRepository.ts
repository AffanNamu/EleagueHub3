import {
  doc,
  getDoc,
  updateDoc,
  deleteDoc,
  runTransaction,
  collection,
  query,
  where,
  orderBy,
  limit,
  getDocs,
  documentId,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import {
  isValidUsername,
  isValidUsernameFormat,
  isReservedUsername,
  normalizeToBaseUsername,
  padToMinLength,
  USERNAME_MIN_LENGTH,
  USERNAME_MAX_LENGTH,
} from '@/lib/username';

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

// ─────────────────────────────────────────────────────────────────────────
// USERNAME SYSTEM
//
// Single source of truth for username uniqueness, generation, and editing
// on web — mirrors UserProfileRepository.dart's username section
// (updateUsername / ensureUsernameIfMissing / _reserveAndWriteUsername).
//
// IMPORTANT: reservation + profile update are deliberately TWO SEQUENTIAL
// writes, not one runTransaction(). This mirrors a real bug fix made on
// the Flutter side: Firestore Security Rules evaluate every write in a
// transaction against the database state as it existed BEFORE that
// transaction's own writes land — a write earlier in a transaction is
// invisible to a rule check on a later write in that SAME transaction.
// The users/{uid} update rule requires exists(usernames/{candidateLower});
// if both writes were bundled into one transaction, that check would
// always evaluate to false and the profile write would be silently
// rejected with permission-denied even for a genuinely available
// username. Splitting into two commits (with rollback if step 2 fails)
// avoids that entirely. See the Flutter-side fix in
// UserProfileRepository.dart for the original diagnosis.
// ─────────────────────────────────────────────────────────────────────────

export class UsernameUnavailableError extends Error {}

/**
 * Best-effort, NON-transactional availability check — safe to call on
 * every keystroke (debounced) for live UI feedback. Does NOT reserve the
 * name; the authoritative check happens inside reserveAndWriteUsername().
 */
export async function isUsernameAvailable(
  candidate: string,
  forUserId: string,
): Promise<boolean> {
  const lower = candidate.trim().toLowerCase();
  if (!isValidUsernameFormat(lower)) return false;

  const snap = await getDoc(doc(db, 'usernames', lower));
  if (!snap.exists()) return true;

  const owner = stringFromAny(snap.data()?.userId);
  return owner === '' || owner === forUserId.trim();
}

async function reserveAndWriteUsername(
  authUid: string,
  candidateLower: string,
  candidateDisplay: string,
  previousLower: string,
): Promise<void> {
  if (!isValidUsername(candidateLower)) {
    throw new UsernameUnavailableError('That username is not allowed.');
  }

  const newRef = doc(db, 'usernames', candidateLower);
  const userRef = doc(db, 'users', authUid);
  const now = Date.now();

  // STEP 1: reserve the new username as its own committed write. Kept as
  // a small transaction purely to race-proof it against two people
  // claiming the same candidate at the same instant — NOT combined with
  // step 2 (see the file-level doc comment for why).
  await runTransaction(db, async (tx) => {
    const newSnap = await tx.get(newRef);
    if (newSnap.exists()) {
      const owner = stringFromAny(newSnap.data()?.userId);
      if (owner && owner !== authUid) {
        throw new UsernameUnavailableError('That username is already taken.');
      }
      // Already reserved by this same user (e.g. a retried call after a
      // prior partial failure) — nothing further to do here.
      return;
    }
    tx.set(newRef, { userId: authUid, createdAtMs: now });
  });

  // STEP 2: point the profile at the now-committed reservation.
  try {
    await updateDoc(userRef, {
      userId: authUid,
      username: candidateDisplay,
      usernameLower: candidateLower,
      updatedAt: now,
    });
  } catch (err) {
    // Roll back so a failed save can't permanently squat on the name.
    try {
      const snap = await getDoc(newRef);
      const owner = stringFromAny(snap.data()?.userId);
      if (snap.exists() && owner === authUid) {
        await deleteDoc(newRef);
      }
    } catch {
      // Best-effort rollback only — the original error matters more.
    }
    throw err;
  }

  // STEP 3: release the OLD reservation, best-effort. The profile
  // already points at the new username regardless of whether this
  // cleanup succeeds.
  if (previousLower && previousLower !== candidateLower) {
    try {
      const oldRef = doc(db, 'usernames', previousLower);
      const oldSnap = await getDoc(oldRef);
      const oldOwner = stringFromAny(oldSnap.data()?.userId);
      if (oldSnap.exists() && oldOwner === authUid) {
        await deleteDoc(oldRef);
      }
    } catch (e) {
      console.warn('[userProfileRepository] failed to release old username reservation:', e);
    }
  }
}

/**
 * Explicit, user-initiated username change. Validates format, rejects
 * reserved words, and enforces uniqueness. Throws
 * UsernameUnavailableError if the name is taken, reserved, or invalid.
 */
export async function updateUsername(
  authUid: string,
  newUsername: string,
  previousLower: string,
): Promise<void> {
  const candidateLower = newUsername.trim().toLowerCase();

  if (!isValidUsernameFormat(candidateLower)) {
    throw new UsernameUnavailableError(
      `Usernames must be ${USERNAME_MIN_LENGTH}-${USERNAME_MAX_LENGTH} characters: letters, numbers, and underscore only.`,
    );
  }
  if (isReservedUsername(candidateLower)) {
    throw new UsernameUnavailableError('That username is reserved. Please choose another.');
  }
  if (previousLower.trim().toLowerCase() === candidateLower) {
    return; // no-op: saving the same username the user already has
  }

  await reserveAndWriteUsername(authUid, candidateLower, candidateLower, previousLower.trim());
}

/**
 * Lazily assigns a username to the given user IF they don't already have
 * one — for both brand-new accounts and pre-existing accounts created
 * before the username system existed. Safe to call repeatedly (no-ops
 * once a username is set). Never throws — this is a best-effort
 * background step, not a user-initiated action.
 */
export async function ensureUsernameIfMissing(
  authUid: string,
  displayName: string,
  currentUsernameLower: string,
): Promise<void> {
  if (currentUsernameLower.trim()) return;

  let base = normalizeToBaseUsername(displayName) || 'user';
  base = padToMinLength(base);
  if (base.length > USERNAME_MAX_LENGTH) base = base.slice(0, USERNAME_MAX_LENGTH);

  const maxAttempts = 20;
  for (let i = 0; i <= maxAttempts; i++) {
    const suffix = i === 0 ? '' : String(i);
    let candidate = base;
    if (suffix) {
      const maxBaseLen = Math.max(1, USERNAME_MAX_LENGTH - suffix.length);
      candidate = `${base.slice(0, maxBaseLen)}${suffix}`;
    }
    if (!isValidUsername(candidate)) continue;

    try {
      await reserveAndWriteUsername(authUid, candidate, candidate, '');
      return;
    } catch (err) {
      if (err instanceof UsernameUnavailableError) continue; // try next suffix
      console.error('[userProfileRepository] ensureUsernameIfMissing attempt failed:', err);
      return;
    }
  }

  // Last-resort: guaranteed-unique suffix derived from the uid itself.
  const uidTail = authUid
    .replace(/[^a-z0-9]/gi, '')
    .toLowerCase()
    .slice(-4)
    .padStart(4, '0');
  const maxBaseLen = Math.max(1, USERNAME_MAX_LENGTH - (uidTail.length + 1));
  const fallback = `${base.slice(0, maxBaseLen)}_${uidTail}`;

  try {
    await reserveAndWriteUsername(authUid, fallback, fallback, '');
  } catch (err) {
    console.error('[userProfileRepository] ensureUsernameIfMissing final fallback failed:', err);
  }
}
