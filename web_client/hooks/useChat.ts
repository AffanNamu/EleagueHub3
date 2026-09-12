'use client';

import { useEffect, useState, useCallback } from 'react';
import { collection, doc, onSnapshot, orderBy, query, limit as fsLimit, where, setDoc, getDocs, updateDoc, writeBatch, serverTimestamp } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { ChatMessage } from '@/types/chat';

export interface OrganizerChatMessage {
  messageId: string;
  senderId: string;
  senderName: string;
  senderPhoto: string;
  text: string;
  imageUrl: string;
  voiceUrl: string;
  voiceDurationMs?: number;
  type: 'text' | 'image' | 'code' | 'voice';
  timestamp: number;
  pinned: boolean;
  deleted: boolean;
  createdAtMs: number;
  pinnedBy: string;
  deletedBy: string;
  replyToMessageId?: string;
  replyToSenderName?: string;
  replyToText?: string;
  replyToType?: string;
}

/** Context of the message being replied to, attached to the next outgoing
 * message — mirrors league_chat_screen.dart's `_replyTo` + the
 * replyToMessageId/replyToSenderName/replyToText/replyToType fields
 * ChatRepository.dart writes on send. */
export interface ChatSendReply {
  messageId: string;
  senderName: string;
  text: string;
  type: string;
}

export interface ChatSendPayload {
  text?: string;
  type?: 'text' | 'image' | 'voice' | 'code';
  imageUrl?: string;
  voiceUrl?: string;
  voiceDurationMs?: number;
  replyTo?: ChatSendReply | null;
}

// --- ORGANIZER CHAT (Master Leagues) ---
function organizerChatCol(masterLeagueId: string) {
  return collection(db, 'master_leagues', masterLeagueId, 'chatroom');
}

export function useOrganizerChat(masterLeagueId: string) {
  const [messages, setMessages] = useState<OrganizerChatMessage[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) return;

    const q = query(
      organizerChatCol(masterLeagueId),
      orderBy('timestamp', 'desc'),
      fsLimit(50),
    );

    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs
          .map((d) => d.data() as any)
          .filter((m) => m.deleted !== true)
          .map((m) => ({
            messageId: m.messageId,
            senderId: m.senderId,
            senderName: m.senderName,
            senderPhoto: m.senderPhoto ?? '',
            text: m.text ?? '',
            imageUrl: m.imageUrl ?? '',
            voiceUrl: m.voiceUrl ?? '',
            voiceDurationMs: Number(m.voiceDurationMs) || 0,
            type: m.type,
            timestamp: Number(m.timestamp) || 0,
            pinned: m.pinned === true,
            deleted: m.deleted === true,
            createdAtMs: Number(m.createdAtMs) || Number(m.timestamp) || 0,
            pinnedBy: m.pinnedBy ?? '',
            deletedBy: m.deletedBy ?? '',
            replyToMessageId: m.replyToMessageId ?? '',
            replyToSenderName: m.replyToSenderName ?? '',
            replyToText: m.replyToText ?? '',
            replyToType: m.replyToType ?? '',
          })) as OrganizerChatMessage[];
        
        setMessages(list.reverse());
        setLoading(false);
      },
      (error) => {
        console.error("Chat Error:", error);
        setLoading(false);
      }
    );

    return () => unsub();
  }, [masterLeagueId]);

  // NOTE: moderation gating (banned/muted) is UI-level only, matching
  // organizer_chat_screen.dart — Firestore rules' validOrganizerChatMessageCreate
  // never checks memberModeration, so the real-time useChatModeration() hook
  // driving the caller's disabled state IS the enforcement here, same as Dart.
  const sendMessage = useCallback(
    async (payload: ChatSendPayload) => {
      const user = auth.currentUser;
      if (!user) throw new Error('Please sign in to continue.');

      const type = payload.type ?? 'text';
      const trimmedText = (payload.text ?? '').trim();
      if (type === 'text' && !trimmedText) return;

      const reply = payload.replyTo;
      const ref = doc(organizerChatCol(masterLeagueId));
      const now = Date.now();

      await setDoc(ref, {
        messageId: ref.id,
        senderId: user.uid,
        senderName: user.displayName || 'User',
        senderPhoto: user.photoURL || '',
        text: trimmedText,
        imageUrl: type === 'image' ? (payload.imageUrl ?? '') : '',
        voiceUrl: type === 'voice' ? (payload.voiceUrl ?? '') : '',
        voiceDurationMs: type === 'voice' ? Math.max(0, payload.voiceDurationMs ?? 0) : 0,
        type: type,
        masterLeagueId,
        timestamp: now,
        createdAt: serverTimestamp(),
        createdAtMs: now,
        pinned: false,
        pinnedAt: null,
        pinnedBy: '',
        deleted: false,
        deletedAt: null,
        deletedBy: '',
        replyToMessageId: reply?.messageId ?? '',
        replyToSenderName: reply?.senderName ?? '',
        replyToText: reply?.text ?? '',
        replyToType: reply?.type ?? '',
      });
    },
    [masterLeagueId],
  );

  const pinMessage = useCallback(
    async (messageId: string) => {
      const col = organizerChatCol(masterLeagueId);

      const prevPinnedSnap = await getDocs(
        query(col, where('pinned', '==', true), orderBy('pinnedAt', 'desc'), fsLimit(1)),
      );
      const prevDoc = prevPinnedSnap.docs[0];

      const batch = writeBatch(db);
      if (prevDoc && prevDoc.id !== messageId) {
        batch.update(prevDoc.ref, { pinned: false, pinnedAt: null, pinnedBy: '' });
      }
      batch.update(doc(col, messageId), {
        pinned: true,
        pinnedAt: serverTimestamp(),
        pinnedBy: auth.currentUser?.uid ?? '',
      });
      await batch.commit();
    },
    [masterLeagueId],
  );

  const unpinMessage = useCallback(
    async (messageId: string) => {
      await updateDoc(doc(organizerChatCol(masterLeagueId), messageId), {
        pinned: false,
        pinnedAt: null,
        pinnedBy: '',
      });
    },
    [masterLeagueId],
  );

  const deleteMessage = useCallback(
    async (messageId: string) => {
      await updateDoc(doc(organizerChatCol(masterLeagueId), messageId), {
        deleted: true,
        deletedAt: serverTimestamp(),
        deletedBy: auth.currentUser?.uid ?? '',
        pinned: false,
        pinnedAt: null,
        pinnedBy: '',
      });
    },
    [masterLeagueId],
  );

  return { messages, loading, sendMessage, pinMessage, unpinMessage, deleteMessage };
}

// --- STANDARD LEAGUE CHAT ---
// NOTE (fix): this used to point at 'leagues/{id}/chat', but the actual
// Firestore Security Rules only define 'leagues/{id}/chatroom' — there is
// no rule at all for a 'chat' subcollection, so with default-deny every
// read/write here was being rejected. Renamed to match the rules (and
// the Flutter app's ChatRepository, which has always used 'chatroom').
function leagueChatCol(leagueId: string) {
  return collection(db, 'leagues', leagueId, 'chatroom');
}

export function useChat(leagueId: string) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!leagueId) return;

    const q = query(leagueChatCol(leagueId), orderBy('timestamp', 'asc'), fsLimit(100));

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const msgs = snapshot.docs.map(doc => ({
        ...doc.data()
      })) as ChatMessage[];
      
      setMessages(msgs);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching chat:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [leagueId]);

  // NOTE: like organizer chat, moderation gating (banned/muted) is UI-level
  // only — league_chat_screen.dart's _chatBlocked/_chatReadOnly gate the
  // send buttons using state from _watchModerationState(), and
  // validChatMessageCreate below never checks moderation docs. The caller
  // is expected to gate via useChatModeration() + canManageLeague() first.
  const sendMessage = async (payload: ChatSendPayload) => {
    const user = auth.currentUser;
    if (!user) throw new Error('Please sign in to continue.');

    const type = payload.type ?? 'text';
    const trimmedText = (payload.text ?? '').trim();
    if (type === 'text' && !trimmedText) return;

    const reply = payload.replyTo;
    const messageId = doc(leagueChatCol(leagueId)).id;
    const nowMs = Date.now();

    const newMessage: Partial<ChatMessage> = {
      messageId,
      senderId: user.uid,
      senderName: user.displayName || 'Player',
      senderPhoto: user.photoURL || '',
      text: trimmedText,
      imageUrl: type === 'image' ? (payload.imageUrl ?? '') : '',
      voiceUrl: type === 'voice' ? (payload.voiceUrl ?? '') : '',
      voiceDurationMs: type === 'voice' ? Math.max(0, payload.voiceDurationMs ?? 0) : 0,
      type,
      leagueId,
      timestamp: nowMs,
      createdAtMs: nowMs,
      createdAt: serverTimestamp(),
      pinned: false,
      pinnedBy: '',
      deleted: false,
      deletedBy: '',
      replyToMessageId: reply?.messageId ?? '',
      replyToSenderName: reply?.senderName ?? '',
      replyToText: reply?.text ?? '',
      replyToType: reply?.type ?? '',
    };

    try {
      await setDoc(doc(leagueChatCol(leagueId), messageId), newMessage);
    } catch (err: any) {
      console.error("Failed to send message", err);
      throw err;
    }
  };

  const pinMessage = async (messageId: string) => {
    const col = leagueChatCol(leagueId);

    const prevPinnedSnap = await getDocs(
      query(col, where('pinned', '==', true), orderBy('pinnedAt', 'desc'), fsLimit(1)),
    );
    const prevDoc = prevPinnedSnap.docs[0];

    const batch = writeBatch(db);
    if (prevDoc && prevDoc.id !== messageId) {
      batch.update(prevDoc.ref, { pinned: false, pinnedAt: null, pinnedBy: '' });
    }
    batch.update(doc(col, messageId), {
      pinned: true,
      pinnedAt: serverTimestamp(),
      pinnedBy: auth.currentUser?.uid ?? '',
    });
    await batch.commit();
  };

  const unpinMessage = async (messageId: string) => {
    await updateDoc(doc(leagueChatCol(leagueId), messageId), {
      pinned: false,
      pinnedAt: null,
      pinnedBy: '',
    });
  };

  const deleteMessage = async (messageId: string) => {
    await updateDoc(doc(leagueChatCol(leagueId), messageId), {
      deleted: true,
      deletedAt: serverTimestamp(),
      deletedBy: auth.currentUser?.uid ?? '',
      pinned: false,
      pinnedAt: null,
      pinnedBy: '',
    });
  };

  return { messages, loading, error, sendMessage, pinMessage, unpinMessage, deleteMessage };
}

/**
 * Standalone (non-hook) send, for flows that don't otherwise subscribe to
 * the chat via useChat — e.g. fixtures_screen.dart's share-to-league-chat,
 * which posts a single image message. Mirrors useChat's sendMessage shape.
 */
export async function sendLeagueImageMessageWeb(leagueId: string, imageUrl: string) {
  if (!auth.currentUser) throw new Error('Please sign in and try again.');

  const messageId = doc(leagueChatCol(leagueId)).id;
  const nowMs = Date.now();

  const newMessage: Partial<ChatMessage> = {
    messageId,
    senderId: auth.currentUser.uid,
    senderName: auth.currentUser.displayName || 'Player',
    senderPhoto: auth.currentUser.photoURL || '',
    text: '',
    imageUrl,
    voiceUrl: '',
    type: 'image',
    leagueId,
    timestamp: nowMs,
    createdAtMs: nowMs,
    createdAt: serverTimestamp(),
    pinned: false,
    pinnedBy: '',
    deleted: false,
    deletedBy: '',
  };

  await setDoc(doc(leagueChatCol(leagueId), messageId), newMessage);
}
