'use client';

import { useState, useEffect } from 'react';
import { collection, query, onSnapshot, orderBy, limit as fsLimit, doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { ChatMessage } from '@/types/chat';

export function useGlobalChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Adjusted for standard behavior since the original got overwritten
  const [accessStatus, setAccessStatus] = useState<'approved' | 'pending' | 'rejected' | null>('approved');
  const [accessLoading, setAccessLoading] = useState(false);

  useEffect(() => {
    const q = query(collection(db, 'global_chatroom'), orderBy('timestamp', 'asc'), fsLimit(100));

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const msgs = snapshot.docs.map(doc => ({
        ...doc.data()
      })) as ChatMessage[];
      
      setMessages(msgs);
      setLoading(false);
      setError(null);
    }, (err) => {
      console.error("Error fetching global chat:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const sendMessage = async (text: string) => {
    if (!auth.currentUser || !text.trim()) return;

    const messageId = doc(collection(db, 'global_chatroom')).id;
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
      leagueId: 'global', // fallback identifier
      timestamp: nowMs,
      createdAtMs: nowMs,
      createdAt: serverTimestamp(),
      pinned: false,
      pinnedBy: '',
      deleted: false,
      deletedBy: ''
    };

    try {
      await setDoc(doc(collection(db, 'global_chatroom'), messageId), newMessage);
    } catch (err: any) {
      console.error("Failed to send message", err);
      throw err;
    }
  };

  const requestAccess = async () => {
    setAccessLoading(true);
    // Add logic here to request access to the global chat via Firestore
    setTimeout(() => {
      setAccessStatus('pending');
      setAccessLoading(false);
    }, 500);
  };

  return { messages, loading, error, sendMessage, accessStatus, accessLoading, requestAccess };
}
