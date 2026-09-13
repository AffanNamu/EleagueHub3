import { useState, useEffect } from 'react';
import { collection, doc, query, orderBy, limit, where, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { ChatMessage } from '@/lib/chat/chatRepository';

export function useGlobalChat(enabled: boolean) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [pinnedMessage, setPinnedMessage] = useState<ChatMessage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // firestore.rules gates get/list on globalChatroom behind
    // canAccessGlobalChat() (an approved globalChatRequests doc, or super
    // admin). Subscribing unconditionally on mount fired this query before
    // the caller's access status was known, so anyone not yet approved got
    // a permission-denied error here instead of ever reaching the "Request
    // Access" screen. Only subscribe once the caller confirms access.
    if (!enabled) {
      // Resets state for the case `enabled` flips true -> false while
      // mounted (e.g. access revoked mid-session); on first mount with
      // `enabled` already false these are all already at their defaults.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setMessages([]);
      setPinnedMessage(null);
      setLoading(false);
      setError(null);
      return;
    }

    // 1. Watch Messages
    const qMsgs = query(collection(db, 'globalChatroom'), orderBy('createdAtMs', 'desc'), limit(120));
    const unsubMsgs = onSnapshot(
      qMsgs,
      (snap) => {
        setMessages(snap.docs.map(d => ({ ...d.data(), messageId: d.id } as ChatMessage)));
        setLoading(false);
      },
      (err) => {
        // Without this, a query failure (e.g. permission-denied) left
        // `loading` stuck at true forever with no error ever surfaced —
        // the screen just spins indefinitely with nothing in the console
        // to diagnose from.
        console.error('[useGlobalChat] messages query failed:', err);
        setError(err.message);
        setLoading(false);
      },
    );

    // 2. Watch Pinned Message
    const qPinned = query(collection(db, 'globalChatroom'), where('pinned', '==', true), orderBy('pinnedAt', 'desc'), limit(1));
    const unsubPinned = onSnapshot(
      qPinned,
      (snap) => {
        setPinnedMessage(snap.docs.length > 0 ? { ...snap.docs[0].data(), messageId: snap.docs[0].id } as ChatMessage : null);
      },
      (err) => {
        console.error('[useGlobalChat] pinned-message query failed:', err);
      },
    );

    return () => { unsubMsgs(); unsubPinned(); };
  }, [enabled]);

  return { messages, pinnedMessage, loading, error };
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
