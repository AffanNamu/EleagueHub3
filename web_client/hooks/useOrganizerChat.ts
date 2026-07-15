import { useState, useEffect } from 'react';
import { collection, query, onSnapshot, orderBy, limit, doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { ChatMessage } from '@/types/chat';

export function useOrganizerChat(masterLeagueId: string) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!masterLeagueId) return;

    // Fetch the latest 100 messages for this Master League
    const q = query(
      collection(db, 'master_leagues', masterLeagueId, 'chatroom'),
      orderBy('timestamp', 'desc'),
      limit(100)
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      // Reverse the array so the newest messages are at the bottom of the UI
      const msgs = snapshot.docs.map(doc => ({
        ...doc.data()
      })) as ChatMessage[];
      
      setMessages(msgs.reverse());
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching organizer chat:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [masterLeagueId]);

  const sendMessage = async (text: string) => {
    if (!auth.currentUser || !text.trim()) return;

    const messageId = doc(collection(db, 'master_leagues', masterLeagueId, 'chatroom')).id;
    const nowMs = Date.now();

    const newMessage: Partial<ChatMessage> = {
      messageId,
      senderId: auth.currentUser.uid,
      senderName: auth.currentUser.displayName || 'Player',
      senderPhoto: auth.currentUser.photoURL || '',
      text: text.trim(),
      imageUrl: '',
      voiceUrl: '',
      type: 'text',
      leagueId: masterLeagueId, // Reusing this field for the parent ID reference
      timestamp: nowMs,
      createdAtMs: nowMs,
      createdAt: serverTimestamp(),
      pinned: false,
      pinnedBy: '',
      deleted: false,
      deletedBy: ''
    };

    try {
      await setDoc(doc(db, 'master_leagues', masterLeagueId, 'chatroom', messageId), newMessage);
    } catch (err: any) {
      console.error("Failed to send message", err);
      throw err;
    }
  };

  return { messages, loading, error, sendMessage };
}
