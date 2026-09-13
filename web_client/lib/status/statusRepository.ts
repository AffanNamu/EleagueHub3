// web_client/lib/status/statusRepository.ts
//
// Web port of lib/features/status/data/status_repository.dart — the
// temporary Status/Story system. Firestore path: users/{uid}/statuses/{id}.
// Field names and the 24h (max 26h server-enforced) lifetime match the
// Dart model exactly, and the write shape matches firestore.rules'
// `match /statuses/{statusId}` validation byte-for-byte (see
// firestore.rules ~line 1174) so a status created here is readable by the
// mobile app and vice versa.

import {
  collection,
  doc,
  getDocs,
  onSnapshot,
  query,
  where,
  deleteDoc,
  Unsubscribe,
  DocumentData,
  QueryDocumentSnapshot,
} from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

export interface UserStatus {
  statusId: string;
  userId: string;
  imageUrl: string;
  caption: string;
  createdAtMs: number;
  expiresAtMs: number;
}

// Mirrors UserStatus.lifetime in user_status.dart.
export const STATUS_LIFETIME_MS = 24 * 60 * 60 * 1000;

export class StatusRepositoryError extends Error {}

function statusesCol(userId: string) {
  return collection(db, 'users', userId, 'statuses');
}

function fromDoc(d: QueryDocumentSnapshot<DocumentData>): UserStatus {
  const data = d.data();
  return {
    statusId: d.id,
    userId: (data.userId || '').trim(),
    imageUrl: (data.imageUrl || '').trim(),
    caption: (data.caption || '').trim(),
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    expiresAtMs: typeof data.expiresAtMs === 'number' ? data.expiresAtMs : 0,
  };
}

/** Creates a new 24h status for the signed-in user. */
export async function createStatusWeb(params: { imageUrl: string; caption?: string }): Promise<void> {
  const authUid = auth.currentUser?.uid.trim() || '';
  if (!authUid) throw new StatusRepositoryError('Please sign in and try again.');

  const url = params.imageUrl.trim();
  if (!url) throw new StatusRepositoryError('Please select an image for your status.');

  const { setDoc } = await import('firebase/firestore');
  const ref = doc(statusesCol(authUid));
  const now = Date.now();
  const caption = (params.caption || '').trim().slice(0, 200);

  await setDoc(ref, {
    statusId: ref.id,
    userId: authUid,
    imageUrl: url,
    caption,
    createdAtMs: now,
    expiresAtMs: now + STATUS_LIFETIME_MS,
  });
}

/** Subscribes to whether [userId] currently has at least one active status — drives the status ring. */
export function watchHasActiveStatusWeb(userId: string, callback: (active: boolean) => void): Unsubscribe {
  const uid = userId.trim();
  if (!uid) {
    callback(false);
    return () => {};
  }

  const q = query(statusesCol(uid), where('expiresAtMs', '>', Date.now()));
  return onSnapshot(
    q,
    (snap) => callback(!snap.empty),
    () => callback(false),
  );
}

/** One-time fetch of every active status for [userId], oldest first, for the viewer. */
export async function fetchActiveStatusesWeb(userId: string): Promise<UserStatus[]> {
  const uid = userId.trim();
  if (!uid) return [];

  const q = query(statusesCol(uid), where('expiresAtMs', '>', Date.now()));
  const snap = await getDocs(q);
  return snap.docs.map(fromDoc).sort((a, b) => a.createdAtMs - b.createdAtMs);
}

/** Deletes a status. Only the owner may do this (also enforced server-side). */
export async function deleteStatusWeb(params: { userId: string; statusId: string }): Promise<void> {
  const authUid = auth.currentUser?.uid.trim() || '';
  if (params.userId.trim() !== authUid) {
    throw new StatusRepositoryError('You can only delete your own status.');
  }
  await deleteDoc(doc(db, 'users', authUid, 'statuses', params.statusId));
}
