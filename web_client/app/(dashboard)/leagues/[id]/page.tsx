'use client';

import { useParams, useRouter } from 'next/navigation';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { LeagueAccessGate } from '@/components/leagues/LeagueAccessGate';
import { StandingsTable } from '@/components/leagues/StandingsTable';
import { LayoutGrid, ArrowLeft, Loader2, Trophy, Settings, Activity, CalendarDays, MessageSquare, GitMerge, Users, CalendarPlus } from 'lucide-react';
import Link from 'next/link';
import QRCode from 'react-qr-code';

import { auth } from '@/lib/firebase';
import { useEffect, useState } from 'react';
import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export default function LeagueDetailsScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league, loading: leagueLoading, error: leagueError } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);
  
  const [isAdmin, setIsAdmin] = useState(false);
  useEffect(() => {
    if (auth.currentUser) {
      getDoc(doc(db, 'leagues', leagueId, 'members', auth.currentUser.uid)).then(snap => {
        if (snap.exists() && ['owner', 'admin'].includes(snap.data().role)) setIsAdmin(true);
      });
    }
  }, [leagueId]);

  if (leagueLoading || teamsLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  if (leagueError || !league) return <div className="text-brand-red p-4">{leagueError || 'Not found'}</div>;

  return (
    <LeagueAccessGate league={league}>
      <div className="space-y-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            {league.name}
            <span className="text-xs px-2 py-1 bg-brand-lime/20 text-brand-lime rounded-md border border-brand-lime/30 uppercase tracking-wider">{league.status}</span>
          </h1>
          <p className="text-gray-400 mt-1">{league.description}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <Glass className="p-1 md:p-4">
            <div className="flex items-center gap-2 mb-4 px-3 pt-2">
              <Trophy className="w-5 h-5 text-brand-lime" />
              <h2 className="text-xl font-bold text-white">Live Standings</h2>
            </div>
            <StandingsTable teams={teams} format={league?.format} />
          </Glass>

      {/* Join Code & QR Code display */}
      <div className="mt-4 p-4 bg-brand-surfaceDark border border-brand-lime/30 rounded-xl flex items-center justify-between">
        <div>
          <p className="text-xs text-brand-lime font-bold uppercase tracking-wider mb-1">League Join Code</p>
          <p className="text-2xl font-mono text-white tracking-widest">{league.id.substring(0, 8).toUpperCase()}</p>
        </div>
        <div className="p-2 bg-white rounded-lg">
           <QRCode value={league.id} size={48} />
        </div>
      </div>

        </div>

        <div className="space-y-6">
          <Glass className="p-5 space-y-4">
            <h3 className="font-semibold text-white flex items-center gap-2"><Activity className="w-4 h-4 text-brand-lime" /> Actions</h3>
            
            <Link href={`/leagues/${leagueId}/matches`} className="w-full flex items-center justify-between p-3 bg-brand-surface rounded-xl hover:bg-white/10 transition-colors">
              <div className="flex items-center gap-3">
                <CalendarDays className="w-5 h-5 text-white" />
                <span className="font-medium text-white">Fixtures & Results</span>
              </div>
            </Link>

            <Link href={`/leagues/${leagueId}/knockout`} className="w-full flex items-center justify-between p-3 bg-brand-surface rounded-xl hover:bg-white/10 transition-colors">
              <div className="flex items-center gap-3">
                <GitMerge className="w-5 h-5 text-[#8B5CF6]" />
                <span className="font-medium text-white">Knockout Bracket</span>
              </div>
            </Link>

            <Link href={`/leagues/${leagueId}/chat`} className="w-full flex items-center justify-between p-3 bg-[#38BDF8]/10 border border-[#38BDF8]/30 rounded-xl hover:bg-[#38BDF8]/20 transition-colors">
              <div className="flex items-center gap-3">
                <MessageSquare className="w-5 h-5 text-[#38BDF8]" />
                <span className="font-medium text-[#38BDF8]">League Chat Room</span>
              </div>
            </Link>

            {isAdmin && (
              <>
                <div className="pt-4 mt-2 border-t border-white/10">
                  <h4 className="text-xs font-bold text-gray-500 uppercase tracking-widest mb-3">Admin Tools</h4>
                </div>

                <Link href={`/leagues/${leagueId}/admin/settings`} className="w-full flex items-center justify-between p-3 bg-brand-surface border border-white/5 rounded-xl hover:bg-white/10 transition-colors mt-2">
                  <div className="flex items-center gap-3">
                    <Settings className="w-5 h-5 text-gray-400" />
                    <span className="font-medium text-gray-300">League Settings</span>
                  </div>
                </Link>


                <Link href={`/leagues/${leagueId}/admin/teams`} className="w-full flex items-center justify-between p-3 bg-brand-surface border border-white/5 rounded-xl hover:bg-white/10 transition-colors">
                  <div className="flex items-center gap-3">
                    <Users className="w-5 h-5 text-white" />
                    <span className="font-medium text-white">Manage Teams</span>
                  </div>
                </Link>

                <Link href={`/leagues/${leagueId}/admin/groups`} className="w-full flex items-center justify-between p-3 bg-brand-surface border border-white/5 rounded-xl hover:bg-white/10 transition-colors">
                  <div className="flex items-center gap-3">
                    <LayoutGrid className="w-5 h-5 text-white" />
                    <span className="font-medium text-white">Group Overview</span>
                  </div>
                </Link>


                <Link href={`/leagues/${leagueId}/admin/fixtures`} className="w-full flex items-center justify-between p-3 bg-brand-surface border border-white/5 rounded-xl hover:bg-white/10 transition-colors">
                  <div className="flex items-center gap-3">
                    <CalendarPlus className="w-5 h-5 text-white" />
                    <span className="font-medium text-white">Schedule Fixtures</span>
                  </div>
                </Link>

                <Link href={`/leagues/${leagueId}/admin/knockout-draw`} className="w-full flex items-center justify-between p-3 bg-brand-surface border border-white/5 rounded-xl hover:bg-white/10 transition-colors">
                  <div className="flex items-center gap-3">
                    <GitMerge className="w-5 h-5 text-white" />
                    <span className="font-medium text-white">Knockout Draw</span>
                  </div>
                </Link>


                <Link href={`/leagues/${leagueId}/admin`} className="w-full flex items-center justify-between p-3 bg-brand-red/10 border border-brand-red/30 rounded-xl hover:bg-brand-red/20 transition-colors group">
                  <div className="flex items-center gap-3">
                    <Settings className="w-5 h-5 text-brand-red group-hover:rotate-90 transition-transform" />
                    <span className="font-bold text-brand-red">Score Editor</span>
                  </div>
                </Link>

                <Link href={`/leagues/${leagueId}/admin/knockouts`} className="w-full flex items-center justify-between p-3 bg-[#8B5CF6]/10 border border-[#8B5CF6]/30 rounded-xl hover:bg-[#8B5CF6]/20 transition-colors group">
                  <div className="flex items-center gap-3">
                    <GitMerge className="w-5 h-5 text-[#8B5CF6]" />
                    <span className="font-bold text-[#8B5CF6]">Knockout Editor</span>
                  </div>
                </Link>

              </>
            )}
          </Glass>
        </div>
      </div>
          </div>
    </LeagueAccessGate>
  );
}
