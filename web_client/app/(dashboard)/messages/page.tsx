'use client';

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import Link from 'next/link';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { usePrivateThreads } from '@/hooks/usePrivateChat';
import { fetchUserProfileByUserId } from '@/lib/services/userProfileRepository';
import { getOtherParticipant, PrivateThread } from '@/lib/chat/privateChatRepository';
import { Loader2, MessageCircle, Image as ImageIcon, Mic } from 'lucide-react';

interface ThreadRow {
  thread: PrivateThread;
  name: string;
  photoUrl: string;
}

function previewFor(t: PrivateThread): { icon: ReactNode; text: string } {
  if (t.lastMessage === '📷 Photo') return { icon: <ImageIcon className="w-3.5 h-3.5" />, text: 'Photo' };
  if (t.lastMessage === '🎤 Voice message') return { icon: <Mic className="w-3.5 h-3.5" />, text: 'Voice message' };
  return { icon: null, text: t.lastMessage || 'Say hello 👋' };
}

export default function MessagesInboxPage() {
  const [authUid, setAuthUid] = useState<string | null>(null);
  const { threads, loading } = usePrivateThreads();
  const [rows, setRows] = useState<ThreadRow[]>([]);
  const [resolving, setResolving] = useState(true);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function resolveNames() {
      if (!authUid) return;
      setResolving(true);
      const resolved = await Promise.all(
        threads.map(async (t) => {
          const other = getOtherParticipant(t, authUid);
          const profile = other ? await fetchUserProfileByUserId(other) : null;
          return { thread: t, name: profile?.teamName || 'User', photoUrl: profile?.photoUrl || '' };
        }),
      );
      if (!cancelled) {
        setRows(resolved);
        setResolving(false);
      }
    }

    resolveNames();
    return () => { cancelled = true; };
  }, [threads, authUid]);

  return (
    <div className="max-w-3xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      <div>
        <h1 className="text-2xl md:text-3xl font-black text-white flex items-center gap-3">
          <MessageCircle className="w-6 h-6 text-[#BEF264]" /> Messages
        </h1>
        <p className="text-gray-400 mt-1 text-sm font-semibold">Your private conversations.</p>
      </div>

      {loading || resolving ? (
        <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]" /></div>
      ) : rows.length === 0 ? (
        <div className="text-center bg-[#0B1221] border border-[#1E293B] rounded-3xl p-16">
          <MessageCircle className="w-12 h-12 text-[#1E293B] mx-auto mb-4" />
          <p className="text-white font-black text-lg">No conversations yet.</p>
          <p className="text-sm font-medium text-gray-500 mt-1">Premium users can start a chat from any profile.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map(({ thread, name, photoUrl }) => {
            const preview = previewFor(thread);
            return (
              <Link
                key={thread.id}
                href={`/messages/${thread.id}`}
                className="flex items-center gap-4 p-4 bg-[#0B1221] border border-[#1E293B] rounded-2xl hover:bg-[#1E293B]/50 hover:border-white/10 transition-colors group"
              >
                <div className="w-12 h-12 rounded-full bg-[#1E293B] border border-white/5 overflow-hidden shrink-0 flex items-center justify-center">
                  {photoUrl ? (
                    <img src={photoUrl} alt={name} className="w-full h-full object-cover" />
                  ) : (
                    <MessageCircle className="w-5 h-5 text-gray-500" />
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-black text-white text-sm truncate group-hover:text-[#BEF264] transition-colors">{name}</div>
                  <div className="flex items-center gap-1.5 text-xs font-semibold text-gray-400 truncate mt-0.5">
                    {preview.icon}
                    {preview.text}
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
