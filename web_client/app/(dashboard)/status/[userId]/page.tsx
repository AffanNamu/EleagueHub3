'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { fetchUserProfileByUserId } from '@/lib/services/userProfileRepository';
import { fetchActiveStatusesWeb, deleteStatusWeb, UserStatus } from '@/lib/status/statusRepository';
import { Loader2, X, Trash2 } from 'lucide-react';

// Web port of status_viewer_screen.dart — full-screen story viewer with
// per-item progress bars, auto-advance, and tap-left/right navigation.
const PER_STATUS_MS = 6000;

export default function StatusViewerPage() {
  const params = useParams();
  const router = useRouter();
  const userId = ((params.userId as string) || '').trim();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [items, setItems] = useState<UserStatus[]>([]);
  const [displayName, setDisplayName] = useState('User');
  const [index, setIndex] = useState(0);
  const [progress, setProgress] = useState(0);
  const [authUid, setAuthUid] = useState<string | null>(null);

  const rafRef = useRef<number | null>(null);
  const startRef = useRef<number>(0);
  const pausedAtRef = useRef<number | null>(null);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged((u) => setAuthUid(u?.uid || null));
    return () => unsub();
  }, []);

  const close = useCallback(() => {
    if (window.history.length > 1) router.back();
    else router.push(`/profile/${userId}`);
  }, [router, userId]);

  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError('');
      try {
        const [statuses, profile] = await Promise.all([
          fetchActiveStatusesWeb(userId),
          fetchUserProfileByUserId(userId),
        ]);
        if (cancelled) return;
        setItems(statuses);
        setDisplayName(profile?.teamName || 'User');
        setIndex(0);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [userId]);

  const goNext = useCallback(() => {
    setIndex((i) => {
      if (i >= items.length - 1) {
        close();
        return i;
      }
      return i + 1;
    });
  }, [items.length, close]);

  const goPrevious = useCallback(() => {
    setIndex((i) => Math.max(0, i - 1));
  }, []);

  // Progress/auto-advance loop for the current item. The first rAF tick
  // computes an elapsed of ~0 on its own, so no synchronous setProgress(0)
  // is needed here.
  useEffect(() => {
    if (items.length === 0) return;
    startRef.current = performance.now();
    pausedAtRef.current = null;

    function tick(now: number) {
      if (pausedAtRef.current !== null) {
        rafRef.current = requestAnimationFrame(tick);
        return;
      }
      const elapsed = now - startRef.current;
      const value = Math.min(1, elapsed / PER_STATUS_MS);
      setProgress(value);
      if (value >= 1) {
        goNext();
        return;
      }
      rafRef.current = requestAnimationFrame(tick);
    }
    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [index, items.length]);

  function handlePointerDown() {
    pausedAtRef.current = performance.now();
  }
  function handlePointerUp() {
    if (pausedAtRef.current !== null) {
      startRef.current += performance.now() - pausedAtRef.current;
      pausedAtRef.current = null;
    }
  }

  function handleTap(e: React.MouseEvent<HTMLDivElement>) {
    const width = e.currentTarget.clientWidth;
    const x = e.clientX - e.currentTarget.getBoundingClientRect().left;
    if (x < width / 3) goPrevious();
    else goNext();
  }

  async function handleDelete() {
    const current = items[index];
    if (!current) return;
    if (!window.confirm('Delete this status? This cannot be undone.')) return;
    try {
      await deleteStatusWeb({ userId, statusId: current.statusId });
      const remaining = items.filter((_, i) => i !== index);
      if (remaining.length === 0) {
        close();
        return;
      }
      setItems(remaining);
      setIndex((i) => Math.min(i, remaining.length - 1));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
    }
  }

  const isOwner = !!authUid && authUid === userId;
  const current = items[index];

  return (
    <div className="fixed inset-0 z-50 bg-black flex items-center justify-center">
      {loading ? (
        <Loader2 className="w-10 h-10 animate-spin text-white" />
      ) : error ? (
        <MessageState message={error} onClose={close} />
      ) : items.length === 0 || !current ? (
        <MessageState message="No active status right now." onClose={close} />
      ) : (
        <div
          className="relative w-full h-full max-w-md mx-auto select-none"
          onMouseDown={handlePointerDown}
          onMouseUp={handlePointerUp}
          onClick={handleTap}
        >
          <img
            src={current.imageUrl}
            alt="Status"
            className="absolute inset-0 w-full h-full object-cover"
            draggable={false}
          />

          <div className="absolute left-2 right-2 top-2 flex gap-1">
            {items.map((_, i) => (
              <div key={i} className="flex-1 h-[3px] rounded bg-white/25 overflow-hidden">
                <div
                  className="h-full bg-white"
                  style={{ width: `${i < index ? 100 : i === index ? progress * 100 : 0}%` }}
                />
              </div>
            ))}
          </div>

          <div className="absolute left-3 right-3 top-5 flex items-center gap-2">
            <span className="flex-1 text-white font-black text-sm truncate" style={{ textShadow: '0 1px 6px rgba(0,0,0,0.6)' }}>
              {displayName}
            </span>
            {isOwner && (
              <button onClick={(e) => { e.stopPropagation(); handleDelete(); }} className="p-1.5 text-white/90 hover:text-white">
                <Trash2 className="w-5 h-5" />
              </button>
            )}
            <button onClick={(e) => { e.stopPropagation(); close(); }} className="p-1.5 text-white/90 hover:text-white">
              <X className="w-5 h-5" />
            </button>
          </div>

          {current.caption && (
            <p
              className="absolute left-4 right-4 bottom-8 text-center text-white font-bold text-sm"
              style={{ textShadow: '0 1px 6px rgba(0,0,0,0.6)' }}
            >
              {current.caption}
            </p>
          )}
        </div>
      )}
    </div>
  );
}

function MessageState({ message, onClose }: { message: string; onClose: () => void }) {
  return (
    <div className="relative w-full h-full flex items-center justify-center px-6">
      <p className="text-white/70 font-semibold text-center">{message}</p>
      <button onClick={onClose} className="absolute top-2 right-2 p-2 text-white">
        <X className="w-5 h-5" />
      </button>
    </div>
  );
}
