import { useState, useEffect } from 'react';
import { collection, query, onSnapshot, orderBy, limit, doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { SupabaseEdgeNotificationsService } from '@/lib/services/supabaseEdgeNotifications';
import { ChatMessage } from '@/types/chat';

export function useChat(leagueId: string) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!leagueId) return;

    // Fetch the latest 100 messages for this league
    const q = query(
      collection(db, 'leagues', leagueId, 'chat'),
      orderBy('timestamp', 'asc'),
      limit(100)
    );

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

  const sendMessage = async (text: string) => {
    if (!auth.currentUser || !text.trim()) return;

    const messageId = doc(collection(db, 'leagues', leagueId, 'chat')).id;
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
      leagueId,
      timestamp: nowMs,
      createdAtMs: nowMs,
      createdAt: serverTimestamp(),
      pinned: false,
      pinnedBy: '',
      deleted: false,
      deletedBy: ''
    };

    try {
      await setDoc(doc(db, 'leagues', leagueId, 'chat', messageId), newMessage);
    } catch (err: any) {
      console.error("Failed to send message", err);
      throw err;
    }
  };

  return { messages, loading, error, sendMessage };
}
