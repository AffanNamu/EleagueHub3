'use client';

import { useEffect, useState, useCallback } from 'react';
import { collection, doc, onSnapshot, orderBy, query, limit as fsLimit, setDoc, getDoc, serverTimestamp } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

export interface OrganizerChatMessage {
  messageId: string;
  senderId: string;
  senderName: string;
  senderPhoto: string;
  text: string;
  imageUrl: string;
  voiceUrl: string;
  type: 'text' | 'image' | 'code' | 'voice';
  timestamp: number;
  pinned: boolean;
  deleted: boolean;
  createdAtMs: number;
  pinnedBy: string;
  deletedBy: string;
}

export function useOrganizerChat(masterLeagueId: string) {
  const [messages, setMessages] = useState<OrganizerChatMessage[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!masterLeagueId) return;

    const q = query(
      collection(db, 'master_leagues', masterLeagueId, 'chatroom'),
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
            type: m.type,
            timestamp: Number(m.timestamp) || 0,
            pinned: m.pinned === true,
            deleted: m.deleted === true,
            createdAtMs: Number(m.createdAtMs) || Number(m.timestamp) || 0,
            pinnedBy: m.pinnedBy ?? '',
            deletedBy: m.deletedBy ?? '',
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

  const checkCanSend = useCallback(async (): Promise<string | null> => {
    const user = auth.currentUser;
    if (!user) return 'Please sign in to send messages.';

    try {
      const modSnap = await getDoc(doc(db, 'master_leagues', masterLeagueId, 'memberModeration', user.uid));
      if (modSnap.exists()) {
        const mod = modSnap.data();
        if (mod.chatBanned === true) return 'You are banned from this organizer chat.';
        if (mod.chatMuted === true) return 'You are muted in this organizer chat.';
      }
    } catch (e: any) {
      console.warn("Bypassed moderation read check due to rules:", e.message);
    }
    return null;
  }, [masterLeagueId]);

  const sendMessage = useCallback(
    async (text: string, type: 'text' | 'image' | 'voice' = 'text', fileUrl: string = '') => {
      const user = auth.currentUser;
      if (!user) throw new Error('Please sign in to continue.');

      const blockReason = await checkCanSend();
      if (blockReason) throw new Error(blockReason);

      const trimmed = text.trim();
      if (!trimmed && type === 'text') return;

      const ref = doc(collection(db, 'master_leagues', masterLeagueId, 'chatroom'));
      const now = Date.now();

      // STRICT MATCH to your working payload. No extra unauthorized fields!
      await setDoc(ref, {
        messageId: ref.id,
        senderId: user.uid,
        senderName: user.displayName || 'User',
        senderPhoto: user.photoURL || '',
        text: type === 'text' ? trimmed.slice(0, 4000) : trimmed,
        imageUrl: type === 'image' ? fileUrl : '',
        voiceUrl: type === 'voice' ? fileUrl : '',
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
      });
    },
    [masterLeagueId, checkCanSend],
  );

  return { messages, loading, sendMessage };
}
