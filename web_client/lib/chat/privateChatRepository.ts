import { collection, doc, getDoc, setDoc, query, where, orderBy, limit, onSnapshot, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { detectPremiumUser } from '@/lib/leagues/leaguesRepository';
import {
  isPaidPlanActive,
  runWithRateLimit,
  RateLimitExceededError,
  RATE_LIMIT_KIND_CHAT_MESSAGES,
  FREE_CHAT_MESSAGES_PER_DAY,
} from '@/lib/plans/rateLimitService';

export interface PrivateThread {
  id: string;
  participantIds: string[];
  initiatedBy: string;
  lastMessage: string;
  lastMessageAtMs: number;
  lastSenderId: string;
  createdAtMs: number;
}

export interface PrivateMessage {
  id: string;
  senderId: string;
  type: 'text' | 'image' | 'voice';
  text: string;
  imageUrl: string;
  voiceUrl: string;
  createdAtMs: number;
}

// Deterministic Thread ID (Mirrors Flutter)
export function getThreadId(uidA: string, uidB: string): string {
  const sorted = [uidA, uidB].sort();
  return `dm_${sorted[0]}_${sorted[1]}`;
}

export function getOtherParticipant(thread: PrivateThread, selfUid: string): string {
  return thread.participantIds.find(id => id !== selfUid) || '';
}

// ── ACCESS CONTROL ──
export async function checkChatAccessWeb(authUid: string, targetUid: string) {
  if (!authUid || !targetUid || authUid === targetUid) return 'locked';

  // Check Block Status
  const blockedBySnap = await getDoc(doc(db, 'users', authUid, 'blocked_by', targetUid));
  const blockedUsersSnap = await getDoc(doc(db, 'users', authUid, 'blocked_users', targetUid));
  if (blockedBySnap.exists() || blockedUsersSnap.exists()) return 'blocked';

  const threadId = getThreadId(authUid, targetUid);
  
  try {
    const threadSnap = await getDoc(doc(db, 'private_threads', threadId));
    if (threadSnap.exists()) return 'threadExists';
  } catch (e: any) {
    if (e.code !== 'permission-denied') throw e;
  }

  // Check if user is premium to start a new chat
  const isPremium = await detectPremiumUser(authUid);

  return isPremium ? 'canStart' : 'locked';
}

export async function startOrGetThreadWeb(authUid: string, targetUid: string): Promise<PrivateThread> {
  const access = await checkChatAccessWeb(authUid, targetUid);
  if (access === 'blocked') throw new Error('You cannot message this user.');
  if (access === 'locked') throw new Error('Starting a private chat requires a Premium plan.');

  const threadId = getThreadId(authUid, targetUid);
  const ref = doc(db, 'private_threads', threadId);

  const existing = await getDoc(ref);
  if (existing.exists()) return { id: existing.id, ...existing.data() } as PrivateThread;

  const now = Date.now();
  const data: PrivateThread = {
    id: threadId,
    participantIds: [authUid, targetUid].sort(),
    initiatedBy: authUid,
    lastMessage: '',
    lastMessageAtMs: now,
    lastSenderId: '',
    createdAtMs: now,
  };

  await setDoc(ref, data);
  return data;
}

// ── SENDING MESSAGES (Batch Write) ──
export async function sendPrivateMessageWeb(
  threadId: string, 
  senderId: string, 
  type: 'text' | 'image' | 'voice', 
  text: string, 
  imageUrl: string = '', 
  voiceUrl: string = ''
) {
  const threadRef = doc(db, 'private_threads', threadId);
  const msgRef = doc(collection(threadRef, 'messages'));
  const now = Date.now();

  let lastMessagePreview = text;
  if (type === 'image') lastMessagePreview = '📷 Photo';
  if (type === 'voice') lastMessagePreview = '🎤 Voice message';

  const messageData = {
    senderId,
    type,
    text,
    imageUrl,
    voiceUrl,
    createdAtMs: now,
  };
  const threadUpdate = {
    lastMessage: lastMessagePreview,
    lastMessageAtMs: now,
    lastSenderId: senderId,
  };

  const isPaid = await isPaidPlanActive(senderId);
  if (isPaid) {
    const batch = writeBatch(db);
    batch.set(msgRef, messageData);
    batch.set(threadRef, threadUpdate, { merge: true });
    await batch.commit();
    return;
  }

  try {
    await runWithRateLimit({
      uid: senderId,
      kind: RATE_LIMIT_KIND_CHAT_MESSAGES,
      maxPerDay: FREE_CHAT_MESSAGES_PER_DAY,
      writeMore: (tx) => {
        tx.set(msgRef, messageData);
        tx.set(threadRef, threadUpdate, { merge: true });
      },
    });
  } catch (e) {
    if (e instanceof RateLimitExceededError) throw new Error(e.message);
    throw e;
  }
}
