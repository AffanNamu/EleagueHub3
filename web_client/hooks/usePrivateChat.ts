import { useState, useEffect } from 'react';
import { collection, query, where, orderBy, onSnapshot, limit } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { PrivateThread, PrivateMessage, sendPrivateMessageWeb } from '@/lib/chat/privateChatRepository';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';

export function usePrivateThreads() {
  const [threads, setThreads] = useState<PrivateThread[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubAuth = auth.onAuthStateChanged(user => {
      if (!user) {
        setThreads([]);
        setLoading(false);
        return;
      }

      const q = query(
        collection(db, 'private_threads'),
        where('participantIds', 'array-contains', user.uid),
        orderBy('lastMessageAtMs', 'desc')
      );

      const unsubSnap = onSnapshot(q, (snap) => {
        setThreads(snap.docs.map(d => ({ id: d.id, ...d.data() } as PrivateThread)));
        setLoading(false);
      }, (err) => {
        console.error(err);
        setLoading(false);
      });

      return () => unsubSnap();
    });

    return () => unsubAuth();
  }, []);

  return { threads, loading };
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
    // Important: Cloudinary requires resourceType: 'video' for audio files
    const { secureUrl } = await uploadImageFile({ file, folder: `chat_voice_messages/private/${threadId}`, resourceType: 'video' });
    await sendPrivateMessageWeb(threadId, authUid, 'voice', '', '', secureUrl);
  };

  return { messages, loading, sendText, sendImage, sendVoice };
}
