import { useState, useEffect } from 'react';
import { collection, query, where, orderBy, onSnapshot, limit } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { PrivateThread, PrivateMessage, sendPrivateMessageWeb } from '@/lib/chat/privateChatRepository';
import { uploadImageFile, uploadAudioFile } from '@/lib/cloudinary/cloudinaryUpload';

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

  useEffect(() => {
    if (!threadId) return;

    const q = query(
      collection(db, 'private_threads', threadId, 'messages'),
      orderBy('createdAtMs', 'desc'),
      limit(100)
    );

    const unsub = onSnapshot(q, (snap) => {
      setMessages(snap.docs.map(d => ({ id: d.id, ...d.data() } as PrivateMessage)));
      setLoading(false);
    });

    return () => unsub();
  }, [threadId]);

  const sendText = async (text: string) => {
    if (!authUid) throw new Error('Not authenticated');
    await sendPrivateMessageWeb(threadId, authUid, 'text', text);
  };

  const sendImage = async (file: File) => {
    if (!authUid) throw new Error('Not authenticated');
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
