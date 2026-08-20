'use client';

import { useCallback, useEffect, useState } from 'react';
import {
  collection,
  onSnapshot,
  orderBy,
  query,
  where,
  limit as fsLimit,
} from 'firebase/firestore';
import { onAuthStateChanged } from 'firebase/auth';
import { auth, db } from '@/lib/firebase';
import { PrivateMessage, PrivateThread, privateMessageFromDoc, privateThreadFromDoc } from '@/lib/models/privateChat';
import {
  sendPrivateText,
  sendPrivateImage,
  sendPrivateVoice,
  uploadPrivateChatImage,
  uploadPrivateChatVoice,
} from '@/lib/services/privateChatRepository';

/**
 * Streams the signed-in user's DM inbox, ordered by most recent message.
 * Waits for auth state before querying (unlike some of the older hooks in
 * this codebase that read auth.currentUser synchronously at mount) since
 * the underlying Firestore rule requires signedIn() and a query fired
 * before auth resolves would just fail with permission-denied.
 */
export function usePrivateThreads() {
  const [threads, setThreads] = useState<PrivateThread[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let unsubSnapshot: (() => void) | null = null;

    const unsubAuth = onAuthStateChanged(auth, (user) => {
      if (unsubSnapshot) {
        unsubSnapshot();
        unsubSnapshot = null;
      }

      if (!user) {
        setThreads([]);
        setLoading(false);
        return;
      }

      const q = query(
        collection(db, 'private_threads'),
        where('participantIds', 'array-contains', user.uid),
        orderBy('lastMessageAtMs', 'desc'),
      );

      unsubSnapshot = onSnapshot(
        q,
        (snap) => {
          setThreads(snap.docs.map((d) => privateThreadFromDoc(d.id, d.data())));
          setLoading(false);
        },
        (err) => {
          console.error('[usePrivateThreads] stream error:', err);
          setLoading(false);
        },
      );
    });

    return () => {
      unsubAuth();
      if (unsubSnapshot) unsubSnapshot();
    };
  }, []);

  return { threads, loading };
}

/**
 * Streams messages for one thread (newest first, capped at 100 — matches
 * PrivateChatRepository.dart's watchMessages default) plus send helpers
 * for text/image/voice.
 */
export function usePrivateChat(threadId: string) {
  const [messages, setMessages] = useState<PrivateMessage[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!threadId) return;

    const q = query(
      collection(db, 'private_threads', threadId, 'messages'),
      orderBy('createdAtMs', 'desc'),
      fsLimit(100),
    );

    const unsub = onSnapshot(
      q,
      (snap) => {
        setMessages(snap.docs.map((d) => privateMessageFromDoc(d.id, d.data())));
        setLoading(false);
      },
      (err) => {
        console.error('[usePrivateChat] stream error:', err);
        setLoading(false);
      },
    );

    return () => unsub();
  }, [threadId]);

  const sendText = useCallback(
    async (text: string) => {
      const uid = auth.currentUser?.uid;
      if (!uid) throw new Error('Please sign in to continue.');
      await sendPrivateText(threadId, uid, text);
    },
    [threadId],
  );

  const sendImage = useCallback(
    async (file: File) => {
      const uid = auth.currentUser?.uid;
      if (!uid) throw new Error('Please sign in to continue.');
      const { secureUrl } = await uploadPrivateChatImage(threadId, file);
      await sendPrivateImage(threadId, uid, secureUrl);
    },
    [threadId],
  );

  const sendVoice = useCallback(
    async (blob: Blob) => {
      const uid = auth.currentUser?.uid;
      if (!uid) throw new Error('Please sign in to continue.');
      const { secureUrl } = await uploadPrivateChatVoice(threadId, blob);
      await sendPrivateVoice(threadId, uid, secureUrl);
    },
    [threadId],
  );

  return { messages, loading, sendText, sendImage, sendVoice };
}
