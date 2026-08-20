// lib/services/privateChatRepository.ts
//
// Mirrors lib/features/chat/data/private_chat_repository.dart. New on
// web — this feature didn't exist here before.

import { doc, getDoc, setDoc, collection, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { uploadImageFile, uploadAudioFile } from '@/lib/cloudinary/cloudinaryUpload';
import { PrivateThread, privateThreadFromDoc } from '@/lib/models/privateChat';

export class PrivateChatError extends Error {}

export type PrivateChatAccess = 'threadExists' | 'canStart' | 'locked' | 'blocked';

export interface PrivateChatAccessResult {
  access: PrivateChatAccess;
  existingThreadId?: string;
}

/** Deterministic thread id for a pair of users, matching the Dart repo. */
export function threadIdFor(uidA: string, uidB: string): string {
  const sorted = [uidA, uidB].sort();
  return `dm_${sorted[0]}_${sorted[1]}`;
}

// ── Plan gating ──────────────────────────────────────────────────────────
// Port of UserProfile.hasPlanActive / premiumActive from user_profile.dart.
// 'basic' is confirmed free (MasterLeaguePlan.basic.isFree == true); pro/
// elite are paid and gated by planExpiresAtMs.
function isPlanFree(planId: string): boolean {
  return planId === 'basic';
}

export function hasPlanActive(data: Record<string, unknown> | undefined): boolean {
  if (!data) return false;
  const nowMs = Date.now();
  const planId = typeof data.activePlanId === 'string' ? data.activePlanId.trim() : '';

  if (planId === 'basic' || planId === 'pro' || planId === 'elite') {
    if (isPlanFree(planId)) return true;
    const planExpiresAtMs = typeof data.planExpiresAtMs === 'number' ? data.planExpiresAtMs : 0;
    return planExpiresAtMs > nowMs;
  }

  // Backward compatibility: old premium user gets league (and DM) access.
  const isPremium = data.isPremium === true;
  if (!isPremium) return false;
  const premiumExpiresAtMs = typeof data.premiumExpiresAtMs === 'number' ? data.premiumExpiresAtMs : 0;
  if (premiumExpiresAtMs <= 0) return isPremium;
  return premiumExpiresAtMs > nowMs;
}

// ── Blocking ─────────────────────────────────────────────────────────────
async function isBlockedEitherWay(authUid: string, otherUid: string): Promise<boolean> {
  const [blockedByMe, blockedByThem] = await Promise.all([
    getDoc(doc(db, 'users', authUid, 'blocked_users', otherUid)),
    getDoc(doc(db, 'users', authUid, 'blocked_by', otherUid)),
  ]);
  return blockedByMe.exists() || blockedByThem.exists();
}

// ── Access check (read-only, for UI button state) ──────────────────────────
export async function checkPrivateChatAccess(
  authUid: string,
  otherUserId: string,
): Promise<PrivateChatAccessResult> {
  try {
    const other = otherUserId.trim();
    if (!other || other === authUid) return { access: 'locked' };

    if (await isBlockedEitherWay(authUid, other)) return { access: 'blocked' };

    const threadId = threadIdFor(authUid, other);
    let threadExists = false;
    try {
      const snap = await getDoc(doc(db, 'private_threads', threadId));
      threadExists = snap.exists();
    } catch {
      // A thread doc that doesn't exist yet is denied by the `get` rule
      // (resource.data is null) — treat any read failure here as "no
      // thread exists yet" rather than a real access problem.
      threadExists = false;
    }

    if (threadExists) {
      return { access: 'threadExists', existingThreadId: threadId };
    }

    const profileSnap = await getDoc(doc(db, 'users', authUid));
    const canStart = profileSnap.exists() && hasPlanActive(profileSnap.data());

    return { access: canStart ? 'canStart' : 'locked' };
  } catch {
    return { access: 'locked' };
  }
}

// ── Start or get a thread ───────────────────────────────────────────────
export async function startOrGetPrivateThread(
  authUid: string,
  otherUserId: string,
): Promise<PrivateThread> {
  const other = otherUserId.trim();
  if (!other || other === authUid) {
    throw new PrivateChatError('Invalid recipient.');
  }

  if (await isBlockedEitherWay(authUid, other)) {
    throw new PrivateChatError('You cannot message this user.');
  }

  const threadId = threadIdFor(authUid, other);
  const ref = doc(db, 'private_threads', threadId);

  const existing = await getDoc(ref);
  if (existing.exists()) {
    return privateThreadFromDoc(existing.id, existing.data());
  }

  // Only the initiator needs an active paid plan.
  const profileSnap = await getDoc(doc(db, 'users', authUid));
  const canStart = profileSnap.exists() && hasPlanActive(profileSnap.data());
  if (!canStart) {
    throw new PrivateChatError(
      'Starting a private chat requires a Premium plan. Free accounts can reply once a Premium user messages you first.',
    );
  }

  const now = Date.now();
  await setDoc(ref, {
    participantIds: [authUid, other].sort(),
    initiatedBy: authUid,
    lastMessage: '',
    lastMessageAtMs: now,
    lastSenderId: '',
    createdAtMs: now,
  });

  const fresh = await getDoc(ref);
  return privateThreadFromDoc(fresh.id, fresh.data()!);
}

// ── Sending messages ─────────────────────────────────────────────────────
// No plan check here — once a thread exists, both participants (premium
// or free) can reply. Rules enforce that the sender must be a
// participant. Mirrors the exact batch pattern used in
// PrivateChatRepository.dart.

export async function sendPrivateText(
  threadId: string,
  authUid: string,
  text: string,
): Promise<void> {
  const trimmed = text.trim();
  if (!trimmed) return;
  if (trimmed.length > 4000) {
    throw new PrivateChatError('Message is too long.');
  }

  const now = Date.now();
  const threadRef = doc(db, 'private_threads', threadId);
  const msgRef = doc(collection(threadRef, 'messages'));

  const batch = writeBatch(db);
  batch.set(msgRef, {
    senderId: authUid,
    type: 'text',
    text: trimmed,
    imageUrl: '',
    voiceUrl: '',
    createdAtMs: now,
  });
  batch.set(
    threadRef,
    { lastMessage: trimmed, lastMessageAtMs: now, lastSenderId: authUid },
    { merge: true },
  );
  await batch.commit();
}

export async function sendPrivateImage(
  threadId: string,
  authUid: string,
  imageUrl: string,
): Promise<void> {
  const url = imageUrl.trim();
  if (!url) return;

  const now = Date.now();
  const threadRef = doc(db, 'private_threads', threadId);
  const msgRef = doc(collection(threadRef, 'messages'));

  const batch = writeBatch(db);
  batch.set(msgRef, {
    senderId: authUid,
    type: 'image',
    text: '',
    imageUrl: url,
    voiceUrl: '',
    createdAtMs: now,
  });
  batch.set(
    threadRef,
    { lastMessage: '📷 Photo', lastMessageAtMs: now, lastSenderId: authUid },
    { merge: true },
  );
  await batch.commit();
}

export async function sendPrivateVoice(
  threadId: string,
  authUid: string,
  voiceUrl: string,
): Promise<void> {
  const url = voiceUrl.trim();
  if (!url) return;

  const now = Date.now();
  const threadRef = doc(db, 'private_threads', threadId);
  const msgRef = doc(collection(threadRef, 'messages'));

  const batch = writeBatch(db);
  batch.set(msgRef, {
    senderId: authUid,
    type: 'voice',
    text: '',
    imageUrl: '',
    voiceUrl: url,
    createdAtMs: now,
  });
  batch.set(
    threadRef,
    { lastMessage: '🎤 Voice message', lastMessageAtMs: now, lastSenderId: authUid },
    { merge: true },
  );
  await batch.commit();
}

// ── Uploads ──────────────────────────────────────────────────────────────
export async function uploadPrivateChatImage(threadId: string, file: File) {
  return uploadImageFile({ file, folder: `eleaguehub/chatrooms/private/${threadId}` });
}

export async function uploadPrivateChatVoice(threadId: string, blob: Blob) {
  return uploadAudioFile({
    file: blob,
    folder: `chat_voice_messages/private/${threadId}`,
    filename: `voice_${Date.now()}.webm`,
  });
}
