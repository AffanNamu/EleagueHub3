import { collection, doc, setDoc, updateDoc, getDoc, serverTimestamp, writeBatch } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface ChatMessage {
  messageId: string;
  senderId: string;
  senderName: string;
  senderPhoto: string;
  text: string;
  imageUrl: string;
  voiceUrl: string;
  type: 'text' | 'image' | 'voice' | 'code';
  leagueId?: string;
  masterLeagueId?: string;
  timestamp: number;
  createdAt: any;
  createdAtMs: number;
  pinned: boolean;
  pinnedAt: any | null;
  pinnedBy: string;
  deleted: boolean;
  deletedAt: any | null;
  deletedBy: string;
  replyToMessageId: string;
  replyToSenderName: string;
  replyToText: string;
  replyToType: string;
}

export async function sendGlobalMessageWeb(payload: Partial<ChatMessage>) {
  const ref = doc(collection(db, 'globalChatroom'));
  const now = Date.now();

  // STRICT PARITY: Must exactly match `validChatMessageCreate` in firestore.rules
  const messageData: ChatMessage = {
    messageId: ref.id,
    senderId: payload.senderId || '',
    senderName: payload.senderName || 'Player',
    senderPhoto: payload.senderPhoto || '',
    text: payload.text || '',
    imageUrl: payload.imageUrl || '',
    voiceUrl: payload.voiceUrl || '',
    type: payload.type || 'text',
    timestamp: now,
    createdAt: serverTimestamp(),
    createdAtMs: now,
    pinned: false,
    pinnedAt: null,
    pinnedBy: '',
    deleted: false,
    deletedAt: null,
    deletedBy: '',
    replyToMessageId: payload.replyToMessageId || '',
    replyToSenderName: payload.replyToSenderName || '',
    replyToText: payload.replyToText || '',
    replyToType: payload.replyToType || '',
  };

  await setDoc(ref, messageData);
}

export async function pinGlobalMessageWeb(messageId: string, pinnedBy: string, prevPinnedId: string | null) {
  const batch = writeBatch(db);
  const targetRef = doc(db, 'globalChatroom', messageId);

  // Unpin previous
  if (prevPinnedId && prevPinnedId !== messageId) {
    batch.update(doc(db, 'globalChatroom', prevPinnedId), {
      pinned: false,
      pinnedAt: null,
      pinnedBy: '',
    });
  }

  // Pin new (STRICT PARITY: isChatPinUpdate)
  batch.update(targetRef, {
    pinned: true,
    pinnedAt: serverTimestamp(),
    pinnedBy,
  });

  await batch.commit();
}

export async function softDeleteGlobalMessageWeb(messageId: string, deletedBy: string) {
  const ref = doc(db, 'globalChatroom', messageId);
  // STRICT PARITY: isChatSoftDeleteUpdate
  await updateDoc(ref, {
    deleted: true,
    deletedAt: serverTimestamp(),
    deletedBy,
    pinned: false,
    pinnedAt: null,
    pinnedBy: '',
  });
}

export async function requestGlobalChatAccessWeb(userId: string, userName: string, userPhoto: string) {
  const ref = doc(db, 'globalChatRequests', userId);
  const now = Date.now();
  const snap = await getDoc(ref);

  if (snap.exists()) {
    await updateDoc(ref, { status: 'pending', updatedAtMs: now });
  } else {
    await setDoc(ref, { userId, userName, userPhoto, status: 'pending', createdAtMs: now, updatedAtMs: now });
  }
}

export async function updateGlobalChatRequestStatusWeb(userId: string, status: 'approved' | 'rejected') {
  const ref = doc(db, 'globalChatRequests', userId);
  await updateDoc(ref, { status, updatedAtMs: Date.now() });
}
