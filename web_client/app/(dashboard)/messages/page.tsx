'use client';

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import Link from 'next/link';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { usePrivateThreads } from '@/hooks/usePrivateChat';
import { fetchUserProfileByUserId } from '@/lib/services/userProfileRepository';
import { otherParticipant, PrivateThread } from '@/lib/models/privateChat';
import { Loader2, MessageCircle, Image as ImageIcon, Mic } from 'lucide-react';

interface ThreadRow {
  thread: PrivateThread;
  name: string;
  photoUrl: string;
}

function previewFor(t: PrivateThread): { icon: ReactNode; text: string } {
  if (t.lastMessage === '📷 Photo') return { icon: <ImageIcon className="w-3.5 h-3.5" />, text: 'Photo' };
  if (t.lastMessage === '🎤 Voice message')
    return { icon: <Mic className="w-3.5 h-3.5" />, text: 'Voice message' };
  return { icon: null, text: t.lastMessage || 'Say hello' };
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
          const other = otherParticipant(t, authUid);
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
    return () => {
      cancelled = true;
    };
  }, [threads, authUid]);

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <div>
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <MessageCircle className="w-6 h-6 text-brand-lime" /> Messages
        </h1>
        <p className="text-gray-400 mt-1 text-sm">Your private conversations.</p>
      </div>

      {loading || resolving ? (
        <div className="flex justify-center py-16">
          <Loader2 className="w-8 h-8 animate-spin text-brand-lime" />
        </div>
      ) : rows.length === 0 ? (
        <div className="text-center text-sm text-gray-500 py-16">No conversations yet.</div>
      ) : (
        <div className="space-y-2">
          {rows.map(({ thread, name, photoUrl }) => {
            const preview = previewFor(thread);
            return (
              <Link
                key={thread.id}
                href={`/messages/${thread.id}`}
                className="flex items-center gap-3 p-3.5 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:bg-[#1E293B] transition-colors"
              >
                <div className="w-11 h-11 rounded-full bg-[#1E293B] border border-white/10 overflow-hidden shrink-0 flex items-center justify-center">
                  {photoUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={photoUrl} alt={name} className="w-full h-full object-cover" />
                  ) : (
                    <MessageCircle className="w-5 h-5 text-gray-500" />
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-bold text-white text-sm truncate">{name}</div>
                  <div className="flex items-center gap-1 text-xs text-gray-400 truncate">
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
