'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import {
  fetchFollowedOrganizerFeedOnce,
  markAllRead,
  OrganizerFeedEvent,
} from '@/lib/masterLeagues/organizerFeedRepository';
import {
  ArrowLeft, Loader2, Megaphone, Trophy, ShieldCheck, RefreshCw,
  Radio, Clock, User, Network, ChevronRight,
} from 'lucide-react';

function feedIcon(type: string) {
  switch (type.trim().toLowerCase()) {
    case 'announcement': return Megaphone;
    case 'competition_created': return Trophy;
    case 'verification_approved': return ShieldCheck;
    case 'verification_renewed': return RefreshCw;
    default: return Radio;
  }
}

function feedColor(type: string): string {
  switch (type.trim().toLowerCase()) {
    case 'announcement': return '#8B5CF6';
    case 'competition_created': return '#22C55E';
    case 'verification_approved': return '#1D9BF0';
    case 'verification_renewed': return '#14B8A6';
    default: return '#64748B';
  }
}

function formatWhen(ms: number): string {
  if (ms <= 0) return 'Unknown time';
  try {
    return new Date(ms).toLocaleString();
  } catch {
    return 'Unknown time';
  }
}

export default function FollowedOrganizerFeedScreen() {
  const router = useRouter();
  const [uid, setUid] = useState<string | null>(null);
  const [checkedAuth, setCheckedAuth] = useState(false);
  const [loading, setLoading] = useState(true);
  const [items, setItems] = useState<OrganizerFeedEvent[]>([]);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (currentUid: string) => {
    setLoading(true);
    setError(null);
    try {
      const events = await fetchFollowedOrganizerFeedOnce(currentUid);
      setItems(events);
      // Best-effort — mirrors Flutter marking the feed seen once it loads.
      markAllRead(currentUid);
    } catch {
      setItems([]);
      setError('Unable to load organizer updates right now.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged((user) => {
      setUid(user?.uid ?? null);
      setCheckedAuth(true);
      if (user?.uid) load(user.uid);
      else setLoading(false);
    });
    return () => unsub();
  }, [load]);

  const handleItemTap = (item: OrganizerFeedEvent) => {
    if (item.leagueId.trim()) {
      router.push(`/leagues/${item.leagueId.trim()}`);
      return;
    }
    if (item.masterLeagueId.trim()) {
      router.push(`/master-leagues/${item.masterLeagueId.trim()}`);
    }
  };

  return (
    <div className="max-w-5xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mt-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-xl md:text-2xl font-black text-white">Followed Organizer Feed</h1>
        </div>
      </div>

      <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
        <h2 className="text-lg font-black text-white">Organizer Feed</h2>
        <p className="text-sm font-semibold text-gray-400 mt-2 leading-relaxed">
          Latest updates from the organizer workspaces you follow.
        </p>
      </div>

      {!checkedAuth || loading ? (
        <div className="flex justify-center py-20">
          <Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" />
        </div>
      ) : !uid ? (
        <div className="p-16 text-center border border-[#1E293B] bg-[#0B1221] rounded-3xl">
          <Radio className="w-12 h-12 text-gray-600 mx-auto mb-4" />
          <p className="text-white font-black text-lg">Sign in required</p>
          <p className="text-sm text-gray-400 mt-2">Please sign in to view updates from organizers you follow.</p>
        </div>
      ) : error ? (
        <div className="p-6 bg-red-500/10 border border-red-500/30 text-red-500 rounded-2xl text-sm font-bold">
          {error}
        </div>
      ) : items.length === 0 ? (
        <div className="p-16 text-center border border-[#1E293B] bg-[#0B1221] rounded-3xl">
          <Radio className="w-12 h-12 text-gray-600 mx-auto mb-4" />
          <p className="text-white font-black text-lg">No updates yet</p>
          <p className="text-sm text-gray-400 mt-2">Follow organizer workspaces to see their latest activity here.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {items.map((item) => {
            const Icon = feedIcon(item.type);
            const color = feedColor(item.type);
            return (
              <button
                key={item.id}
                onClick={() => handleItemTap(item)}
                className="text-left bg-[#0B1221] border border-[#1E293B] hover:border-white/10 rounded-2xl p-4 transition-colors flex items-start gap-3"
              >
                <div
                  className="w-10 h-10 rounded-full flex items-center justify-center shrink-0 border"
                  style={{ backgroundColor: `${color}1F`, borderColor: `${color}38` }}
                >
                  <Icon className="w-5 h-5" style={{ color }} />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-black text-white">{item.title}</p>
                  <p className="text-xs font-semibold text-gray-400 mt-1 leading-relaxed">{item.message}</p>
                  <div className="flex flex-wrap gap-2 mt-3">
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold bg-[#BEF264]/10 border border-[#BEF264]/20 text-[#BEF264]">
                      <User className="w-3 h-3" /> {item.actorName || 'Organizer'}
                    </span>
                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold bg-[#BEF264]/10 border border-[#BEF264]/20 text-[#BEF264]">
                      <Clock className="w-3 h-3" /> {formatWhen(item.createdAtMs)}
                    </span>
                    {item.masterLeagueId && (
                      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold bg-teal-500/10 border border-teal-500/20 text-teal-400 truncate max-w-full">
                        <Network className="w-3 h-3 shrink-0" /> <span className="truncate">{item.masterLeagueId}</span>
                      </span>
                    )}
                  </div>
                </div>
                <ChevronRight className="w-5 h-5 text-gray-500 shrink-0" />
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
