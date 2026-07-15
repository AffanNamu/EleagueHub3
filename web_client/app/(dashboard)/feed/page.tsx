'use client';

import { useOrganizerFeed } from '@/hooks/useOrganizerFeed';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Activity, Megaphone, Trophy, Star } from 'lucide-react';
import Link from 'next/link';

export default function FollowedOrganizerFeedScreen() {
  const { feed, loading } = useOrganizerFeed();

  if (loading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-brand-lime" /></div>;

  return (
    <div className="space-y-6 max-w-3xl mx-auto pb-10">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
          <Activity className="w-6 h-6 text-brand-lime" />
          My Feed
        </h1>
        <p className="text-gray-400 mt-1">Updates from organizers you follow.</p>
      </div>

      <div className="space-y-4">
        {feed.length === 0 ? (
          <Glass className="p-10 text-center flex flex-col items-center">
            <Activity className="w-16 h-16 text-gray-500 mb-4 opacity-50" />
            <h3 className="text-xl font-bold text-white mb-2">Your feed is quiet</h3>
            <p className="text-gray-400 mb-6">Follow organizers to get updates on their latest tournaments and announcements.</p>
            <Link href="/master-leagues/discovery" className="px-6 py-3 bg-[#38BDF8]/10 text-[#38BDF8] font-bold rounded-xl border border-[#38BDF8]/30 hover:bg-[#38BDF8]/20">
              Discover Hubs
            </Link>
          </Glass>
        ) : (
          feed.map((item) => {
            const isAnnouncement = item.type === 'announcement';
            const isLeague = item.type === 'new_league';
            const Icon = isAnnouncement ? Megaphone : isLeague ? Trophy : Star;
            const colorClass = isAnnouncement ? 'text-[#38BDF8] bg-[#38BDF8]/10 border-[#38BDF8]/20' : 'text-brand-lime bg-brand-lime/10 border-brand-lime/20';

            return (
              <Glass key={item.id} className="p-5 flex gap-4">
                <div className="shrink-0 pt-1">
                  {item.organizerLogo ? (
                    <img src={item.organizerLogo} className="w-12 h-12 rounded-full object-cover" alt="" />
                  ) : (
                    <div className="w-12 h-12 rounded-full bg-brand-surface border border-white/10 flex items-center justify-center">
                      <Icon className="w-5 h-5 text-gray-400" />
                    </div>
                  )}
                </div>
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-bold text-white">{item.organizerName}</span>
                    <span className="text-xs text-gray-500">•</span>
                    <span className="text-xs text-gray-500">{new Date(item.createdAtMs).toLocaleDateString()}</span>
                  </div>
                  
                  {/* Meta Chip mapped from Dart */}
                  <div className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-[10px] font-bold uppercase tracking-wider mb-3 ${colorClass}`}>
                    <Icon className="w-3 h-3" />
                    {isAnnouncement ? 'Announcement' : 'New Tournament'}
                  </div>

                  <h3 className="text-lg font-bold text-white mb-1">{item.title}</h3>
                  <p className="text-sm text-gray-300 mb-4">{item.description}</p>

                  {item.targetId && isLeague && (
                    <Link href={`/leagues/${item.targetId}`} className="inline-block px-4 py-2 bg-brand-surface border border-white/10 rounded-lg text-sm font-bold text-white hover:bg-white/5 transition-colors">
                      View Tournament
                    </Link>
                  )}
                </div>
              </Glass>
            );
          })
        )}
      </div>
    </div>
  );
}
