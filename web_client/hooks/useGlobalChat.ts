import { useState, useEffect } from 'react';
import { collection, doc, query, orderBy, limit, where, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { ChatMessage } from '@/lib/chat/chatRepository';

export function useGlobalChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pinnedMessage, setPinnedMessage] = useState<ChatMessage | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // 1. Watch Messages
    const qMsgs = query(collection(db, 'globalChatroom'), orderBy('createdAtMs', 'desc'), limit(120));
    const unsubMsgs = onSnapshot(qMsgs, (snap) => {
      setMessages(snap.docs.map(d => ({ ...d.data(), messageId: d.id } as ChatMessage)));
      setLoading(false);
    });

    // 2. Watch Pinned Message
    const qPinned = query(collection(db, 'globalChatroom'), where('pinned', '==', true), orderBy('pinnedAt', 'desc'), limit(1));
    const unsubPinned = onSnapshot(qPinned, (snap) => {
      setPinnedMessage(snap.docs.length > 0 ? { ...snap.docs[0].data(), messageId: snap.docs[0].id } as ChatMessage : null);
    });

    return () => { unsubMsgs(); unsubPinned(); };
  }, []);

  return { messages, pinnedMessage, loading };
}

export function useGlobalChatAccess(userId: string | null) {
  const [status, setStatus] = useState<'pending' | 'approved' | 'rejected' | 'none'>('none');
  const [moderation, setModeration] = useState({ muted: false, banned: false });
  // Whether any sender is allowed to pin their own message, toggled from
  // esportlyic-admin via the app/admins doc. Firestore's
  // canPinGlobalMessage() enforces this server-side regardless; this just
  // keeps the UI's pin button from appearing when the write would be rejected.
  const [allowSenderPin, setAllowSenderPin] = useState(false);

  useEffect(() => {
    if (!userId) return;

    // Watch Request Status
    const unsubReq = onSnapshot(doc(db, 'globalChatRequests', userId), (d) => {
      if (d.exists()) setStatus(d.data().status);
      else setStatus('none');
    });

    // Watch Moderation Status
    const unsubMod = onSnapshot(doc(db, 'app', 'chatModeration', 'users', userId), (d) => {
      if (d.exists()) setModeration({ muted: d.data().allChatMuted, banned: d.data().allChatBanned });
    });

    // Watch sender-pin toggle
    const unsubAdmin = onSnapshot(doc(db, 'app', 'admins'), (d) => {
      if (d.exists()) {
        setAllowSenderPin(d.data().allowGlobalSenderPin === true);
      }
    });

    return () => { unsubReq(); unsubMod(); unsubAdmin(); };
  }, [userId]);

  return { status, moderation, allowSenderPin };
}
