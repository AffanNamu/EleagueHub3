import { collection, doc, getDoc, setDoc, query, where, orderBy, limit, onSnapshot, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { isPaidPlanActive } from '@/lib/plans/rateLimitService';

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
  /// Set once by the RECIPIENT (never the sender -- firestore.rules
  /// enforces this) the moment their client syncs this message. 0/absent
  /// means not yet delivered. Mirrors
  /// lib/features/chat/models/private_message.dart's same field.
  deliveredAtMs?: number;
  /// Set once by the RECIPIENT once they've had the thread open with this
  /// message loaded for a moment. 0/absent means not yet seen.
  seenAtMs?: number;
}

// Mirrors lib/features/chat/presentation/private_chat_screen.dart's
// _handleImagePick() gate -- sending a file attachment in private chat is
// a paid-only action, no free-tier allowance at all (unlike text/voice,
// which are fully unrestricted for everyone). firestore.rules' private DM
// message create rule enforces this authoritatively for type == 'image';
// this error lets the UI show a friendly "upgrade to send files" prompt
// instead of a raw permission-denied.
export class PrivateChatFilesRequirePremiumError extends Error {
  constructor() {
    super('Sending files requires an active Pro or Elite plan. Upgrade your account to send images in private chat.');
    this.name = 'PrivateChatFilesRequirePremiumError';
  }
}

// Starting a private chat is NOT plan-gated at all -- any signed-in user
// with a resolvable profile doc can. This deliberately does NOT check
// activePlanId: userProfileRepository's profile-creation flow
// (lib/features/auth/data/user_profile_repository.dart's
// createIfMissing()) writes a brand-new account's activePlanId as an
// EMPTY STRING, never 'basic' -- so an earlier version of this function
// that checked activePlanId === 'basic' only matched an account some
// other flow had explicitly set to 'basic', not an ordinary free user
// who's never purchased anything. That mismatch made the "Message"
// button look usable while every real attempt still hit
// permission-denied. Only sending a FILE attachment inside a thread
// requires an actual paid plan (isPaidPlanActive, used elsewhere in this
// file) -- text/voice stay available to everyone, and so does starting
// the thread itself. Mirrors firestore.rules' requesterCanStartPrivateChat().
async function hasResolvableProfile(uid: string): Promise<boolean> {
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    return snap.exists();
  } catch (e) {
    console.warn('[privateChatRepository] hasResolvableProfile failed:', e);
    return false;
  }
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

  // Starting a chat isn't plan-gated -- only sending a FILE attachment
  // inside one requires an actual paid plan.
  const canStart = await hasResolvableProfile(authUid);

  return canStart ? 'canStart' : 'locked';
}

export async function startOrGetThreadWeb(authUid: string, targetUid: string): Promise<PrivateThread> {
  const access = await checkChatAccessWeb(authUid, targetUid);
  if (access === 'blocked') throw new Error('You cannot message this user.');
  if (access === 'locked') throw new Error('Please finish setting up your profile before starting a chat.');

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

  // Text/voice messages in private chat are unrestricted -- no daily cap,
  // no plan requirement, for anyone. Only an image/file attachment is
  // ever paid-gated; the caller (usePrivateChat.ts's sendImage()) already
  // pre-checks that and throws PrivateChatFilesRequirePremiumError before
  // this is reached for a free sender, but this stays as a defensive
  // backstop matching firestore.rules' private DM message create rule.
  if (type === 'image') {
    const isPaid = await isPaidPlanActive(senderId);
    if (!isPaid) throw new PrivateChatFilesRequirePremiumError();
  }

  const batch = writeBatch(db);
  batch.set(msgRef, messageData);
  batch.set(threadRef, threadUpdate, { merge: true });
  await batch.commit();
}

// ── DELIVERY / READ RECEIPTS ──
// Mirrors private_chat_repository.dart's markDelivered()/markSeen() --
// best-effort, silent on failure (a side-effect of viewing a thread, not
// a user action), write-once per message id, chunked defensively under
// Firestore's 500-writes-per-batch cap even though a thread's unread
// backlog will never realistically approach that.
async function markReceipt(threadId: string, messageIds: string[], field: 'deliveredAtMs' | 'seenAtMs') {
  if (messageIds.length === 0) return;
  try {
    const now = Date.now();
    const threadRef = doc(db, 'private_threads', threadId);
    for (let i = 0; i < messageIds.length; i += 450) {
      const chunk = messageIds.slice(i, i + 450);
      const batch = writeBatch(db);
      for (const id of chunk) {
        batch.update(doc(collection(threadRef, 'messages'), id), { [field]: now });
      }
      await batch.commit();
    }
  } catch {
    // Best-effort -- see doc comment above.
  }
}

export function markPrivateMessagesDeliveredWeb(threadId: string, messageIds: string[]) {
  return markReceipt(threadId, messageIds, 'deliveredAtMs');
}

export function markPrivateMessagesSeenWeb(threadId: string, messageIds: string[]) {
  return markReceipt(threadId, messageIds, 'seenAtMs');
}
