'use client';

import { useLiveSessions } from '@/hooks/useLiveSessions';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Radio, Users } from 'lucide-react';
import Link from 'next/link';

export default function GlobalLiveScreen() {
  const { sessions, loading, error } = useLiveSessions();

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-brand-red/10 rounded-xl">
            <Radio className="w-6 h-6 text-brand-red animate-pulse" />
          </div>
          <div>
            <h1 className="text-3xl font-bold text-white">Live Matches</h1>
            <p className="text-gray-400">Spectate active games in real-time</p>
          </div>
        </div>
      </div>

      {error && (
        <div className="bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl">
          Error loading live matches: {error}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="w-10 h-10 text-brand-lime animate-spin" />
        </div>
      ) : sessions.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <Radio className="w-16 h-16 text-gray-500 mb-4" />
          <h3 className="text-xl font-semibold text-white">No Live Matches</h3>
          <p className="text-gray-400 mt-2">Check back later or start streaming from the mobile app.</p>
        </Glass>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {sessions.map((session) => (
            <Link href={`/live/${session.id}`} key={session.id}>
              <Glass className="overflow-hidden hover:scale-[1.02] transition-transform cursor-pointer group p-4 border-l-4 border-l-brand-red">
                <div className="flex justify-between items-start mb-4">
                  <div className="bg-brand-red text-white text-[10px] font-black uppercase tracking-wider px-2 py-1 rounded flex items-center gap-1">
                    <Radio className="w-3 h-3 animate-pulse" /> LIVE
                  </div>
                  <div className="flex items-center gap-1 text-xs text-gray-400">
                    <Users className="w-4 h-4" /> {session.viewersCount || 0}
                  </div>
                </div>

                <div className="text-center space-y-2 mb-4">
                  <h3 className="text-lg font-bold text-white">{session.title}</h3>
                  <p className="text-xs text-brand-lime">Hosted by {session.hostName}</p>
                </div>

                <div className="flex justify-between items-center bg-brand-surfaceDark p-3 rounded-xl border border-white/5">
                  <span className="font-bold flex-1 text-right text-sm">{session.homeTeamName}</span>
                  <span className="px-4 font-black text-xl text-brand-lime tabular-nums tracking-widest">
                    {session.homeTeamScore} - {session.awayTeamScore}
                  </span>
                  <span className="font-bold flex-1 text-left text-sm">{session.awayTeamName}</span>
                </div>
              </Glass>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
