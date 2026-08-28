'use client';

import { useEffect, useState, useRef } from 'react';
import type { ChangeEvent } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, getDoc } from 'firebase/firestore';
import { onAuthStateChanged } from 'firebase/auth';
import { auth, db } from '@/lib/firebase';
import { usePrivateMessages } from '@/hooks/usePrivateChat';
import { fetchUserProfileByUserId } from '@/lib/services/userProfileRepository';
import { PrivateChatBubble } from '@/components/chat/PrivateChatBubble';
import { ArrowLeft, ImageIcon, Mic, Send, Loader2, StopCircle } from 'lucide-react';

export default function PrivateChatThreadPage() {
  const router = useRouter();
  const params = useParams();
  const threadId = params.threadId as string;

  const [authUid, setAuthUid] = useState<string | null>(null);
  const [otherName, setOtherName] = useState('Chat');
  const [text, setText] = useState('');
  
  const [sending, setSending] = useState(false);
  const [attaching, setAttaching] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Audio Recording State
  const [isRecording, setIsRecording] = useState(false);
  const [recordTime, setRecordTime] = useState(0);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  const { messages, loading, sendText, sendImage, sendVoice } = usePrivateMessages(threadId);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);

  useEffect(() => {
    let cancelled = false;
    async function loadHeader() {
      if (!threadId || !authUid) return;
      try {
        const snap = await getDoc(doc(db, 'private_threads', threadId));
        if (!snap.exists()) return;
        const ids = (snap.data().participantIds as string[]) || [];
        const other = ids.find((id) => id !== authUid);
        if (!other) return;
        const profile = await fetchUserProfileByUserId(other);
        if (!cancelled) setOtherName(profile?.teamName || 'User');
      } catch (err) {}
    }
    loadHeader();
    return () => { cancelled = true; };
  }, [threadId, authUid]);

  async function handleSendText() {
    if (!text.trim() || sending) return;
    setSending(true);
    setError(null);
    try {
      await sendText(text);
      setText('');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send message.');
    } finally {
      setSending(false);
    }
  }

  async function handlePickImage(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      setError('Image too large. Please select an image under 5 MB.');
      return;
    }

    setAttaching(true);
    setError(null);
    try {
      await sendImage(file);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send image.');
    } finally {
      setAttaching(false);
    }
  }

  // ── NATIVE WEB AUDIO RECORDING ──
  const startRecording = async () => {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream);
      mediaRecorderRef.current = mediaRecorder;
      audioChunksRef.current = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) audioChunksRef.current.push(event.data);
      };

      mediaRecorder.start();
      setIsRecording(true);
      setRecordTime(0);

      timerRef.current = setInterval(() => {
        setRecordTime((prev) => prev + 1);
      }, 1000);
    } catch (err) {
      setError('Microphone permission denied.');
    }
  };

  const stopAndSendRecording = () => {
    if (!mediaRecorderRef.current) return;
    
    setSending(true);
    setIsRecording(false);
    if (timerRef.current) clearInterval(timerRef.current);

    mediaRecorderRef.current.onstop = async () => {
      try {
        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/mp4' });
        const file = new File([audioBlob], `voice_${Date.now()}.mp4`, { type: 'audio/mp4' });
        await sendVoice(file);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Could not send voice message.');
      } finally {
        setSending(false);
        // Turn off mic tracks
        mediaRecorderRef.current?.stream.getTracks().forEach(track => track.stop());
      }
    };

    mediaRecorderRef.current.stop();
  };

  const cancelRecording = () => {
    if (!mediaRecorderRef.current) return;
    setIsRecording(false);
    if (timerRef.current) clearInterval(timerRef.current);
    mediaRecorderRef.current.onstop = () => {
      mediaRecorderRef.current?.stream.getTracks().forEach(track => track.stop());
    };
    mediaRecorderRef.current.stop();
  };

  const selfUid = authUid || auth.currentUser?.uid || '';

  return (
    <div className="flex flex-col h-[calc(100vh-5rem)] max-w-3xl mx-auto bg-[#070B14] md:border-x md:border-[#1E293B]">
      {/* ── HEADER ── */}
      <div className="flex items-center gap-3 p-4 border-b border-[#1E293B] bg-[#0B1221]">
        <button onClick={() => router.push('/messages')} className="w-10 h-10 flex items-center justify-center rounded-xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-white transition-colors">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-lg font-black text-white truncate">{otherName}</h1>
      </div>

      {/* ── MESSAGES ── */}
      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar flex flex-col-reverse gap-1">
        {loading ? (
          <div className="flex justify-center py-10"><Loader2 className="w-6 h-6 animate-spin text-[#BEF264]" /></div>
        ) : messages.length === 0 ? (
          <div className="text-center text-sm font-bold text-gray-500 my-auto">Say hello 👋</div>
        ) : (
          messages.map((m) => (
            <PrivateChatBubble key={m.id} message={m} isMe={m.senderId === selfUid} />
          ))
        )}
      </div>

      {/* ── INPUT AREA ── */}
      <div className="p-4 bg-[#0B1221] border-t border-[#1E293B]">
        {error && <p className="text-xs font-bold text-red-500 mb-2">{error}</p>}

        {isRecording ? (
          <div className="flex items-center gap-3 p-3 rounded-2xl bg-[#1E293B] border border-red-500/30">
            <div className="w-3 h-3 rounded-full bg-red-500 animate-pulse shrink-0" />
            <span className="flex-1 text-sm font-black text-white">Recording… {recordTime}s</span>
            <button onClick={cancelRecording} disabled={sending} className="px-4 py-2 rounded-xl bg-white/5 hover:bg-white/10 text-xs font-bold text-gray-300 disabled:opacity-50">Cancel</button>
            <button onClick={stopAndSendRecording} disabled={sending} className="px-4 py-2 rounded-xl bg-[#BEF264] text-[#0F172A] text-xs font-black flex items-center gap-2 disabled:opacity-50 shadow-lg shadow-[#BEF264]/20">
              {sending ? <Loader2 className="w-3 h-3 animate-spin" /> : <Send className="w-3 h-3" />} Send
            </button>
          </div>
        ) : (
          <div className="flex items-center gap-2">
            <label className="w-12 h-12 flex items-center justify-center rounded-2xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-gray-400 hover:text-white cursor-pointer shrink-0 transition-colors border border-white/5">
              {attaching ? <Loader2 className="w-5 h-5 animate-spin" /> : <ImageIcon className="w-5 h-5" />}
              <input type="file" accept="image/*" className="hidden" onChange={handlePickImage} disabled={attaching} />
            </label>
            
            <button onClick={startRecording} disabled={attaching || sending} className="w-12 h-12 flex items-center justify-center rounded-2xl bg-[#1E293B]/50 hover:bg-[#1E293B] text-gray-400 hover:text-white shrink-0 disabled:opacity-50 transition-colors border border-white/5">
              <Mic className="w-5 h-5" />
            </button>
            
            <input
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') handleSendText(); }}
              placeholder="Type a message..."
              className="flex-1 px-4 py-3 rounded-2xl bg-[#1E293B]/50 border border-white/5 text-sm font-semibold text-white placeholder:text-gray-500 outline-none focus:border-[#BEF264]/50 transition-colors"
            />
            
            <button onClick={handleSendText} disabled={sending || !text.trim()} className="w-12 h-12 flex items-center justify-center rounded-2xl bg-[#BEF264] text-[#0F172A] shrink-0 disabled:opacity-50 hover:brightness-110 shadow-lg shadow-[#BEF264]/20 transition-all">
              {sending ? <Loader2 className="w-5 h-5 animate-spin" /> : <Send className="w-5 h-5" />}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
