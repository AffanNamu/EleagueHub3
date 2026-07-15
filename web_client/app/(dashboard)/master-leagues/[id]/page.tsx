'use client';

import { useParams, useRouter } from 'next/navigation';
import { useMasterLeagueDetail } from '@/hooks/useMasterLeagueDetail';
import { useMasterLeagueTournaments } from '@/hooks/useMasterLeagueTournaments';
import { useAnnouncements } from '@/hooks/useAnnouncements';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, Network, Trophy, Users, ShieldCheck, Megaphone, Link as LinkIcon, MessageSquare, ShieldAlert } from 'lucide-react';
import Link from 'next/link';
import { auth } from '@/lib/firebase';

export default function MasterLeagueDetailsScreen() {
  const params = useParams();
  const router = useRouter();
  const workspaceId = params.id as string;

  const { workspace, loading: workspaceLoading, error: workspaceError } = useMasterLeagueDetail(workspaceId);
  const { leagues, loading: leaguesLoading } = useMasterLeagueTournaments(workspaceId);
  const { announcements, loading: announcementsLoading } = useAnnouncements(workspaceId);

  if (workspaceLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-[#38BDF8] animate-spin" /></div>;
  if (workspaceError || !workspace) return <div className="text-brand-red p-4">{workspaceError || 'Not found'}</div>;

  const isVerified = workspace.organizerProfile?.isVerified;

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
      </div>

      {/* Identity Hero */}
      <Glass className="p-6 md:p-10 relative overflow-hidden flex flex-col md:flex-row items-center md:items-start gap-6 border-t-4 border-t-transparent border-t-[#38BDF8]">
        <div className="w-24 h-24 md:w-32 md:h-32 bg-brand-surface border-4 border-brand-navy rounded-full overflow-hidden shrink-0 z-10 shadow-2xl flex items-center justify-center">
          {workspace.organizerProfile?.logoUrl ? (
            <img src={workspace.organizerProfile.logoUrl} className="w-full h-full object-cover" alt="" />
          ) : (
            <Network className="w-12 h-12 text-gray-500" />
          )}
        </div>
        
        <div className="flex-1 text-center md:text-left z-10 space-y-3">
          <div className="flex flex-col md:flex-row md:items-center gap-2 md:gap-4">
            <h1 className="text-3xl md:text-4xl font-black text-white">{workspace.name}</h1>
            {isVerified && (
              <span className="inline-flex items-center gap-1 px-3 py-1 bg-brand-lime/10 text-brand-lime border border-brand-lime/30 rounded-full text-xs font-bold uppercase tracking-wider w-fit mx-auto md:mx-0">
                <ShieldCheck className="w-4 h-4" /> Verified Organizer
              </span>
            )}
          </div>
          <p className="text-[#38BDF8] font-bold">@{(workspace.organizerProfile?.name || 'Organizer').replace(/\s+/g, '').toLowerCase()}</p>
          
          <div className="flex items-center justify-center md:justify-start gap-6 pt-2">
            <div className="text-center md:text-left">
              <span className="block text-2xl font-black text-white">{workspace.followersCount || 0}</span>
              <span className="text-xs text-gray-400 uppercase tracking-widest font-bold">Followers</span>
            </div>
            <div className="text-center md:text-left">
              <span className="block text-2xl font-black text-white">{leagues.length}</span>
              <span className="text-xs text-gray-400 uppercase tracking-widest font-bold">Competitions</span>
            </div>
          </div>
        </div>

        <div className="flex flex-col gap-3 w-full md:w-auto z-10">
          <button className="w-full md:w-48 px-6 py-3 bg-[#38BDF8] text-brand-navy font-black rounded-xl hover:bg-[#38BDF8]/90 transition-colors shadow-lg shadow-[#38BDF8]/20">
            Follow Organizer
          </button>
          <Link href={`/master-leagues/${workspaceId}/chat`} className="w-full md:w-48 flex items-center justify-center gap-2 px-6 py-3 bg-[#38BDF8]/10 text-[#38BDF8] font-bold rounded-xl border border-[#38BDF8]/30 hover:bg-[#38BDF8]/20 transition-colors text-center">
            <MessageSquare className="w-5 h-5" /> Hub Chat
          </Link>
        </div>
      </Glass>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1 space-y-6">
          <Glass className="p-6">
            <h3 className="font-bold text-white mb-3 text-lg">About</h3>
            <p className="text-sm text-gray-300 leading-relaxed">
              {workspace.description || 'Welcome to our official eSports hub. Follow us for the latest tournaments and community events.'}
            </p>
            <div className="mt-6 pt-4 border-t border-white/5 space-y-3">
              <div className="flex items-center gap-3 text-sm text-gray-400 hover:text-[#38BDF8] cursor-pointer transition-colors">
                <LinkIcon className="w-4 h-4" /> <span>discord.gg/invite</span>
              </div>
              <div className="flex items-center gap-3 text-sm text-gray-400 hover:text-[#38BDF8] cursor-pointer transition-colors">
                <LinkIcon className="w-4 h-4" /> <span>twitter.com/organizer</span>
              </div>
            </div>
          </Glass>

          <Glass className="p-0 overflow-hidden border border-[#38BDF8]/20">
            <div className="bg-[#38BDF8]/10 px-6 py-4 flex items-center gap-3 border-b border-[#38BDF8]/20">
              <Megaphone className="w-5 h-5 text-[#38BDF8]" />
              <h3 className="font-bold text-[#38BDF8]">Announcements</h3>
            </div>
            <div className="p-4">
              {announcementsLoading ? (
                <div className="flex justify-center py-4"><Loader2 className="w-6 h-6 animate-spin text-[#38BDF8]" /></div>
              ) : announcements.length === 0 ? (
                <p className="text-sm text-gray-500 text-center py-4">No recent announcements.</p>
              ) : (
                <div className="space-y-4">
                  {announcements.map(ann => (
                    <div key={ann.id} className="border-l-2 border-[#38BDF8] pl-3 py-1">
                      <h4 className="text-sm font-bold text-white flex items-center gap-2">
                        {ann.title} {ann.pinned && <span className="text-[10px] bg-[#38BDF8]/20 text-[#38BDF8] px-1.5 py-0.5 rounded uppercase tracking-wider">Pinned</span>}
                      </h4>
                      <p className="text-xs text-gray-400 mt-1 line-clamp-2">{ann.message}</p>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </Glass>
        </div>

        <div className="lg:col-span-2">
          <Glass className="p-6">
            <div className="flex items-center gap-3 mb-6">
              <Trophy className="w-6 h-6 text-brand-lime" />
              <h2 className="text-xl font-bold text-white">Competitions</h2>
            </div>

            {leaguesLoading ? (
              <div className="flex justify-center py-10"><Loader2 className="w-8 h-8 text-brand-lime animate-spin" /></div>
            ) : leagues.length === 0 ? (
              <div className="text-center py-10 text-gray-500 border border-dashed border-white/10 rounded-xl">
                <Trophy className="w-12 h-12 mx-auto mb-3 opacity-50" />
                <p>No active competitions found.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {leagues.map((league) => (
                  <Link href={`/leagues/${league.id}`} key={league.id}>
                    <div className="p-4 bg-brand-surface border border-white/5 rounded-xl hover:bg-white/5 transition-colors group flex items-center gap-4">
                      {league.coverImageUrl ? (
                        <img src={league.coverImageUrl} alt={league.name} className="w-14 h-14 rounded-lg object-cover" />
                      ) : (
                        <div className="w-14 h-14 bg-brand-surfaceDark rounded-lg flex items-center justify-center">
                          <Trophy className="w-6 h-6 text-gray-500" />
                        </div>
                      )}
                      <div>
                        <h3 className="font-bold text-white group-hover:text-brand-lime transition-colors line-clamp-1">{league.name}</h3>
                        <p className="text-xs text-gray-400 uppercase tracking-wider mt-1">{league.status}</p>
                      </div>
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </Glass>
        </div>
      </div>
      
      {workspace.ownerId === auth.currentUser?.uid && (
        <div className="lg:col-span-3 mt-6">
          <Glass className="p-6 border border-brand-red/30">
            <div className="flex items-center gap-3 mb-4">
              <ShieldAlert className="w-6 h-6 text-brand-red" />
              <h3 className="font-bold text-white text-lg">Owner Actions</h3>
            </div>
            <div className="flex flex-wrap gap-4">
              <Link href={`/master-leagues/${workspaceId}/admin/discipline`} className="px-6 py-3 bg-brand-red/10 text-brand-red font-bold rounded-xl border border-brand-red/30 hover:bg-brand-red/20 transition-colors flex items-center gap-2">
                <ShieldAlert className="w-5 h-5" /> Discipline Panel
              </Link>
            </div>
          </Glass>
        </div>
      )}
    </div>
  );
}
