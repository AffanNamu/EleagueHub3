import { useState, useEffect } from 'react';
import { collection, query, onSnapshot, orderBy, limit, doc, setDoc, updateDoc, serverTimestamp, getDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';
import { ChatMessage } from '@/types/chat';

export function useGlobalChat() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Access state
  const [accessStatus, setAccessStatus] = useState<'none' | 'pending' | 'approved' | 'rejected'>('none');
  const [accessLoading, setAccessLoading] = useState(true);

  // 1. Listen to the user's specific access request document
  useEffect(() => {
    if (!auth.currentUser) return;
    
    const requestRef = doc(db, 'globalChatRequests', auth.currentUser.uid);
    const unsubscribe = onSnapshot(requestRef, (docSnap) => {
      if (docSnap.exists()) {
        const status = docSnap.data().status?.toLowerCase() || 'none';
        setAccessStatus(status as any);
      } else {
        setAccessStatus('none');
      }
      setAccessLoading(false);
    });

    return () => unsubscribe();
  }, []);

  // 2. Listen to the Global Chat messages (only if approved or super admin)
  useEffect(() => {
    // In a real app, you would also verify the Super Admin UID here
    if (accessStatus !== 'approved' && auth.currentUser?.uid !== 'a0JDUelQW3TEyoXTm4ESuGi7ndq1') {
      setMessages([]);
      setLoading(false);
      return;
    }

    const q = query(
      collection(db, 'globalChatroom'),
      orderBy('createdAtMs', 'desc'),
      limit(120)
    );

    const unsubscribe = onSnapshot(q, (snapshot) => {
      const msgs = snapshot.docs.map(d => d.data()) as ChatMessage[];
      setMessages(msgs.reverse());
      setLoading(false);
    }, (err) => {
      console.error("Error fetching global chat:", err);
      setError(err.message);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [accessStatus]);

  const requestAccess = async () => {
    if (!auth.currentUser) return;
    try {
      const requestRef = doc(db, 'globalChatRequests', auth.currentUser.uid);
      const docSnap = await getDoc(requestRef);
      const nowMs = Date.now();
      
      if (docSnap.exists()) {
        await updateDoc(requestRef, {
          status: 'pending',
          updatedAtMs: nowMs
        });
      } else {
        await setDoc(requestRef, {
          userId: auth.currentUser.uid,
          userName: auth.currentUser.displayName || 'Player',
          userPhoto: auth.currentUser.photoURL || '',
          status: 'pending',
          createdAtMs: nowMs,
          updatedAtMs: nowMs
        });
      }
    } catch (err: any) {
      console.error(err);
      throw err;
    }
  };

  const sendMessage = async (text: string) => {
    if (!auth.currentUser || !text.trim() || accessStatus !== 'approved') return;

    const messageId = doc(collection(db, 'globalChatroom')).id;
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
      timestamp: nowMs,
      createdAtMs: nowMs,
      createdAt: serverTimestamp(),
      pinned: false,
      pinnedBy: '',
      deleted: false,
      deletedBy: ''
    };

    await setDoc(doc(db, 'globalChatroom', messageId), newMessage);
  };

  return { messages, loading, error, sendMessage, accessStatus, accessLoading, requestAccess };
}
