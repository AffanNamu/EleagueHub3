// Mirrors lib/features/verification/data/badge_repository.dart's
// staff/ambassador-related methods (grantStaffBadge/revokeStaffBadge/
// listStaffUserIds) — the subset actually reachable from web's admin tool.
// Badges are stored as a nested map under the "verification" key on the
// user document (users/{uid}.verification.*), matching firestore.rules'
// validVerificationMap allowlist.

import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export async function listStaffUserIds(limitCount = 200): Promise<string[]> {
  try {
    const q = query(collection(db, 'users'), where('verification.staffVerified', '==', true));
    const snap = await getDocs(q);
    return snap.docs.slice(0, limitCount).map((d) => d.id);
  } catch (err) {
    console.error('[badgeRepository] listStaffUserIds failed:', err);
    return [];
  }
}

/** Mirrors BadgeRepository.grantStaffBadge — always admin_granted, source
 * firestore.rules' validVerificationMap requires for staffSource, with no
 * expiry (permanent). */
export async function grantStaffBadgeWeb(userId: string): Promise<void> {
  const ref = doc(db, 'users', userId);
  await setDoc(ref, { verification: {} }, { merge: true });
  await updateDoc(ref, {
    'verification.staffVerified': true,
    'verification.staffSource': 'admin_granted',
    'verification.staffExpiresAt': null,
  });
}

/** Mirrors BadgeRepository.revokeStaffBadge — always admin-initiated, so
 * (unlike the green/organizer revoke helpers) there's no "preserve
 * permanent ownership" branch to consider. */
export async function revokeStaffBadgeWeb(userId: string): Promise<void> {
  const snap = await getDoc(doc(db, 'users', userId));
  const staffVerified = snap.exists() && snap.data()?.verification?.staffVerified === true;
  if (!staffVerified) return;

  await updateDoc(doc(db, 'users', userId), {
    'verification.staffVerified': false,
    'verification.staffSource': null,
    'verification.staffExpiresAt': null,
  });
}
