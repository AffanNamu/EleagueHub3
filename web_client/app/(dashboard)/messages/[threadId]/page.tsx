'use client';

import { useEffect, useState } from 'react';
import type { ChangeEvent } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, getDoc } from 'firebase/firestore';
import { onAuthStateChanged } from 'firebase/auth';
import { auth, db } from '@/lib/firebase';
import { usePrivateChat } from '@/hooks/usePrivateChat';
import { useAudioRecorder } from '@/hooks/useAudioRecorder';
import { fetchUserProfileByUserId } from '@/lib/services/userProfileRepository';
import { PrivateChatBubble } from '@/components/chat/PrivateChatBubble';
import { ArrowLeft, ImageIcon, Mic, Send, Loader2, Check } from 'lucide-react';

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

  const { messages, loading, sendText, sendImage, sendVoice } = usePrivateChat(threadId);
  const recorder = useAudioRecorder();

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
      } catch (err) {
        console.error('[PrivateChatThreadPage] failed to load header:', err);
      }
    }

    loadHeader();
    return () => {
      cancelled = true;
    };
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

  async function handleStartRecording() {
    setError(null);
    try {
      await recorder.start();
    } catch {
      setError('Microphone permission denied.');
    }
  }

  async function handleSendRecording() {
    setSending(true);
    setError(null);
    try {
      const blob = await recorder.stopAndGetBlob();
      await sendVoice(blob);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send voice message.');
    } finally {
      setSending(false);
    }
  }

  const selfUid = authUid || auth.currentUser?.uid || '';

  return (
    <div className="flex flex-col h-[calc(100vh-6rem)] max-w-2xl mx-auto">
      <div className="flex items-center gap-3 pb-4 border-b border-[#1E293B]">
        <button
          onClick={() => router.push('/messages')}
          className="w-9 h-9 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300"
        >
          <ArrowLeft className="w-4 h-4" />
        </button>
        <h1 className="text-lg font-black text-white truncate">{otherName}</h1>
      </div>

      <div className="flex-1 overflow-y-auto py-4 custom-scrollbar">
        {loading ? (
          <div className="flex justify-center py-10">
            <Loader2 className="w-6 h-6 animate-spin text-brand-lime" />
          </div>
        ) : messages.length === 0 ? (
          <div className="text-center text-sm text-gray-500 mt-10">Say hello 👋</div>
        ) : (
          <div className="flex flex-col-reverse">
            {messages.map((m) => (
              <PrivateChatBubble key={m.id} message={m} isMe={m.senderId === selfUid} />
            ))}
          </div>
        )}
      </div>

      {error && <p className="text-xs font-bold text-red-400 mb-2">{error}</p>}

      {recorder.isRecording ? (
        <div className="flex items-center gap-3 p-3 rounded-xl bg-[#0B1221] border border-[#1E293B]">
          <Mic className="w-4 h-4 text-red-400 animate-pulse" />
          <span className="flex-1 text-sm font-bold text-white">
            Recording… {Math.floor(recorder.elapsedMs / 1000)}s
          </span>
          <button
            onClick={recorder.cancel}
            disabled={sending}
            className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-xs font-black text-slate-300 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleSendRecording}
            disabled={sending}
            className="px-3 py-1.5 rounded-lg bg-brand-lime text-slate-900 text-xs font-black flex items-center gap-1 disabled:opacity-50"
          >
            {sending ? <Loader2 className="w-3 h-3 animate-spin" /> : <Check className="w-3 h-3" />}
            Send
          </button>
        </div>
      ) : (
        <div className="flex items-center gap-2 pt-1">
          <label className="w-9 h-9 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300 cursor-pointer shrink-0">
            {attaching ? <Loader2 className="w-4 h-4 animate-spin" /> : <ImageIcon className="w-4 h-4" />}
            <input
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handlePickImage}
              disabled={attaching}
            />
          </label>
          <button
            onClick={handleStartRecording}
            disabled={attaching}
            className="w-9 h-9 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300 shrink-0 disabled:opacity-50"
          >
            <Mic className="w-4 h-4" />
          </button>
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleSendText();
            }}
            placeholder="Message…"
            className="flex-1 px-3 py-2 rounded-lg bg-white/[0.03] border border-white/10 text-sm text-white placeholder:text-slate-600 outline-none focus:border-brand-lime/40"
          />
          <button
            onClick={handleSendText}
            disabled={sending || !text.trim()}
            className="w-9 h-9 flex items-center justify-center rounded-full bg-brand-lime text-slate-900 shrink-0 disabled:opacity-50"
          >
            {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
          </button>
        </div>
      )}
    </div>
  );
}
