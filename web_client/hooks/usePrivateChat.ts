import { useState, useEffect, useRef } from 'react';
import { collection, query, where, orderBy, onSnapshot, limit } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import {
  PrivateThread,
  PrivateMessage,
  sendPrivateMessageWeb,
  PrivateChatFilesRequirePremiumError,
  markPrivateMessagesDeliveredWeb,
  markPrivateMessagesSeenWeb,
} from '@/lib/chat/privateChatRepository';
import { uploadImageFile, uploadAudioFile } from '@/lib/cloudinary/cloudinaryUpload';
import { isPaidPlanActive } from '@/lib/plans/rateLimitService';

export function usePrivateThreads() {
  const [threads, setThreads] = useState<PrivateThread[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const [retryKey, setRetryKey] = useState(0);

  useEffect(() => {
    // auth.onAuthStateChanged does not use a callback's return value for
    // cleanup (it's a plain observer, not an effect) — the
    // `return () => unsubSnap()` this used to have inside the callback was
    // silently discarded and never ran. onAuthStateChanged can fire more
    // than once per session (mount, persisted-auth restore, token
    // refresh), so every re-fire left the previous onSnapshot listener
    // running forever on top of a new one — an unbounded listener leak.
    // Track it outside the callback and tear it down before starting a
    // new one and on unmount (same fix as useLeagues.ts).
    let activeUnsub: (() => void) | null = null;

    const unsubAuth = auth.onAuthStateChanged(user => {
      if (activeUnsub) {
        activeUnsub();
        activeUnsub = null;
      }

      if (!user) {
        setThreads([]);
        setError(null);
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);

      const q = query(
        collection(db, 'private_threads'),
        where('participantIds', 'array-contains', user.uid),
        orderBy('lastMessageAtMs', 'desc')
      );

      activeUnsub = onSnapshot(q, (snap) => {
        setThreads(snap.docs.map(d => ({ id: d.id, ...d.data() } as PrivateThread)));
        setError(null);
        setLoading(false);
      }, (err) => {
        console.error(err);
        // A `.snapshots()`/onSnapshot listener that has errored is dead
        // and will never recover on its own -- surface the error (never
        // fake an empty thread list, which would read as "no
        // conversations" when threads actually failed to load) so the
        // UI can offer a retry that re-runs this effect via retryKey.
        setError(err);
        setLoading(false);
      });
    });

    return () => {
      unsubAuth();
      if (activeUnsub) activeUnsub();
    };
  }, [retryKey]);

  return { threads, loading, error, retry: () => setRetryKey((k) => k + 1) };
}

export function usePrivateMessages(threadId: string) {
  const [messages, setMessages] = useState<PrivateMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const authUid = auth.currentUser?.uid;

  // Delivery/read receipts -- mirrors
  // private_chat_screen.dart's _handleIncomingMessagesForReceipts():
  // "delivered" fires the instant this device's listener syncs a message
  // from the other participant; "seen" fires after a short dwell (this
  // hook/page having stayed mounted with the message loaded), so a
  // message that arrives mid-dwell gets its own fair window. Refs (not
  // state) since these are just in-session dedup guards, not render
  // inputs -- a ref write should never itself trigger a re-render.
  const deliveredHandledRef = useRef<Set<string>>(new Set());
  const seenHandledRef = useRef<Set<string>>(new Set());
  const seenDwellTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!threadId) return;

    const q = query(
      collection(db, 'private_threads', threadId, 'messages'),
      orderBy('createdAtMs', 'desc'),
      limit(100)
    );

    const unsub = onSnapshot(q, (snap) => {
      const list = snap.docs.map(d => ({ id: d.id, ...d.data() } as PrivateMessage));
      setMessages(list);
      setLoading(false);

      const myUid = auth.currentUser?.uid;
      if (!myUid) return;

      const toDeliver: string[] = [];
      for (const m of list) {
        if (!m.senderId || m.senderId === myUid) continue;
        if ((m.deliveredAtMs ?? 0) > 0) continue;
        if (deliveredHandledRef.current.has(m.id)) continue;
        deliveredHandledRef.current.add(m.id);
        toDeliver.push(m.id);
      }
      if (toDeliver.length > 0) {
        void markPrivateMessagesDeliveredWeb(threadId, toDeliver);
      }

      if (seenDwellTimerRef.current) clearTimeout(seenDwellTimerRef.current);
      seenDwellTimerRef.current = setTimeout(() => {
        const toMarkSeen: string[] = [];
        for (const m of list) {
          if (!m.senderId || m.senderId === myUid) continue;
          if ((m.seenAtMs ?? 0) > 0) continue;
          if (seenHandledRef.current.has(m.id)) continue;
          seenHandledRef.current.add(m.id);
          toMarkSeen.push(m.id);
        }
        if (toMarkSeen.length > 0) {
          void markPrivateMessagesSeenWeb(threadId, toMarkSeen);
        }
      }, 1200);
    });

    return () => {
      unsub();
      if (seenDwellTimerRef.current) clearTimeout(seenDwellTimerRef.current);
    };
  }, [threadId]);

  const sendText = async (text: string) => {
    if (!authUid) throw new Error('Not authenticated');
    await sendPrivateMessageWeb(threadId, authUid, 'text', text);
  };

  const sendImage = async (file: File) => {
    if (!authUid) throw new Error('Not authenticated');
    // Backstop re-check -- the caller (messages page) already pre-checks
    // before even reading the file, so this should rarely trigger, but
    // it keeps this function safe to call from anywhere without relying
    // on every caller remembering to check first.
    if (!(await isPaidPlanActive(authUid))) {
      throw new PrivateChatFilesRequirePremiumError();
    }
    const { secureUrl } = await uploadImageFile({ file, folder: `eleaguehub/chatrooms/private/${threadId}` });
    await sendPrivateMessageWeb(threadId, authUid, 'image', '', secureUrl, '');
  };

  const sendVoice = async (file: File) => {
    if (!authUid) throw new Error('Not authenticated');
    const { secureUrl } = await uploadAudioFile({
      file,
      folder: `chat_voice_messages/private/${threadId}`,
      filename: `voice_${Date.now()}.webm`,
    });
    await sendPrivateMessageWeb(threadId, authUid, 'voice', '', '', secureUrl);
  };

  return { messages, loading, sendText, sendImage, sendVoice };
}
