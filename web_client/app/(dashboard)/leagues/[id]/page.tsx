'use client';

import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { StandingsTable } from '@/components/leagues/StandingsTable';
import { LayoutGrid, ArrowLeft, Loader2, Trophy, Settings, Activity, CalendarDays, MessageSquare, GitMerge, Users, CalendarPlus, LogIn, Lock } from 'lucide-react';
import Link from 'next/link';
import QRCode from 'react-qr-code';

import { auth } from '@/lib/firebase';
import { useEffect, useState } from 'react';
import { doc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export default function LeagueDetailsScreen() {
  const params = useParams();
  const router = useRouter();
  const searchParams = useSearchParams();
  
  const leagueId = params.id as string;
  const inviteCode = searchParams.get('invite');

  const { league, loading: leagueLoading, error: leagueError } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading, error: teamsError } = useLeagueTeams(leagueId);
  
  const [isAdmin, setIsAdmin] = useState(false);
  const [isMember, setIsMember] = useState(false);
  const [authLoaded, setAuthLoaded] = useState(false);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged(async (user) => {
      if (user) {
        try {
          const snap = await getDoc(doc(db, 'leagues', leagueId, 'members', user.uid));
          if (snap.exists()) {
            setIsMember(true);
            const role = snap.data().role;
            if (['owner', 'admin'].includes(role)) setIsAdmin(true);
          }
        } catch (err) {
          // If Firebase throws a permission error, it means they aren't a member. We handle it silently.
          console.warn("User is not a member or lacks permission to read member doc.");
        }
      }
      setAuthLoaded(true);
    });
    return () => unsub();
  }, [leagueId]);

  const handleJoinClick = () => {
    if (!auth.currentUser) {
      const returnUrl = `/leagues/${leagueId}${inviteCode ? `?invite=${inviteCode}` : ''}`;
      router.push(`/login?redirect=${encodeURIComponent(returnUrl)}`);
    } else {
      router.push('/leagues');
    }
  };

  if (leagueLoading || !authLoaded) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  if (leagueError || !league) return <div className="text-brand-red p-4">{leagueError || 'Missing or insufficient permission to view this league.'}</div>;

  const displayCode = inviteCode || (league as any).code || (league as any).joinCode || league.id.substring(0, 8).toUpperCase();

  return (
    <div className="space-y-6 max-w-7xl mx-auto pb-16">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            {league.name}
            <span className="text-xs px-2 py-1 bg-brand-lime/10 text-brand-lime rounded-md border border-brand-lime/20 uppercase tracking-wider">{league.status}</span>
          </h1>
          <p className="text-gray-400 mt-1">{league.description}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          
          {/* Main Content Area (Standings / Locked View) */}
          <Glass className="p-1 md:p-4 border border-[#1E293B]">
            <div className="flex items-center gap-2 mb-4 px-3 pt-2">
              <Trophy className="w-5 h-5 text-brand-lime" />
              <h2 className="text-xl font-bold text-white">Live Standings</h2>
            </div>
            
            {/* BUSINESS LOGIC: Lock the standings from anyone who isn't explicitly a member */}
            {!isMember ? (
              <div className="flex flex-col items-center justify-center py-16 px-4 text-center bg-[#070B14] rounded-xl border border-[#1E293B] shadow-inner">
                <div className="w-16 h-16 bg-brand-lime/10 border border-brand-lime/20 rounded-full flex items-center justify-center mb-4">
                  <Lock className="w-8 h-8 text-brand-lime opacity-80" />
                </div>
                <h3 className="text-xl font-black text-white tracking-tight">Standings are Locked</h3>
                <p className="text-sm mt-2 text-gray-500 max-w-sm leading-relaxed">
                  Viewing live standings, match fixtures, and brackets is restricted. You must join this competition to unlock access.
                </p>
                <button
                  onClick={handleJoinClick}
                  className="mt-6 px-6 py-3 bg-brand-lime text-brand-navy font-black rounded-xl hover:brightness-110 transition-all flex items-center gap-2 shadow-lg shadow-brand-lime/10"
                >
                  {auth.currentUser ? 'Use Invite Code to Join' : 'Log in to Join'}
                </button>
              </div>
            ) : teamsLoading ? (
              <div className="flex justify-center py-10"><Loader2 className="w-6 h-6 text-brand-lime animate-spin" /></div>
            ) : teamsError ? (
              <div className="text-center py-10 text-brand-red text-sm">Failed to load standings.</div>
            ) : (
              <StandingsTable teams={teams} format={league?.format} />
            )}
          </Glass>

          {/* Join Code & QR Code display (Public Marketing Info) */}
          <div className="mt-4 p-5 bg-[#0B1221] border border-[#1E293B] shadow-xl rounded-2xl flex flex-col sm:flex-row sm:items-center justify-between gap-6">
            <div className="flex-1">
              <p className="text-xs text-gray-500 font-bold uppercase tracking-wider mb-2">League Join Code</p>
              <div className="bg-[#070B14] border border-[#1E293B] rounded-lg py-2 px-4 inline-block">
                <p className="text-2xl font-mono font-black text-white tracking-widest">{displayCode}</p>
              </div>
              <p className="text-xs text-gray-400 mt-2">Scan the QR code or use this code to enter the competition.</p>
            </div>
            <div className="p-2 bg-white rounded-xl shadow-md shrink-0">
               <QRCode value={`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${displayCode}`} size={80} />
            </div>
          </div>
        </div>

        {/* Sidebar Actions */}
        <div className="space-y-6">
          
          {/* GUEST BANNER */}
          {!isMember && (
            <div className="p-5 bg-gradient-to-br from-[#0B1221] to-[#070B14] border border-[#1E293B] rounded-2xl shadow-xl">
              <h3 className="font-black text-white text-lg flex items-center gap-2 mb-2">
                <Trophy className="w-5 h-5 text-brand-lime" />
                Join Competition
              </h3>
              <p className="text-sm text-gray-400 leading-relaxed mb-5">
                You are viewing this league as a guest. Log in to participate as a team or view full match details!
              </p>
              <button
                onClick={handleJoinClick}
                className="w-full py-3.5 bg-brand-lime text-brand-navy font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2 shadow-lg shadow-brand-lime/20"
              >
                {!auth.currentUser ? (
                  <>
                    <LogIn className="w-4 h-4" /> Log in to Join
                  </>
                ) : (
                  <>
                    <Users className="w-4 h-4" /> Enter Competition
                  </>
                )}
              </button>
            </div>
          )}

          {/* MEMBER ACTIONS - Only show these if they actually joined the league */}
          {isMember && (
            <Glass className="p-5 space-y-4 border border-[#1E293B]">
              <h3 className="font-semibold text-white flex items-center gap-2"><Activity className="w-4 h-4 text-brand-lime" /> Actions</h3>
              
              <Link href={`/leagues/${leagueId}/matches`} className="w-full flex items-center justify-between p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:border-[#2A3A52] transition-colors">
                <div className="flex items-center gap-3">
                  <CalendarDays className="w-5 h-5 text-white" />
                  <span className="font-medium text-white">Fixtures & Results</span>
                </div>
              </Link>

              <Link href={`/leagues/${leagueId}/knockout`} className="w-full flex items-center justify-between p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:border-[#2A3A52] transition-colors">
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
                  <div className="pt-4 mt-2 border-t border-[#1E293B]">
                    <h4 className="text-xs font-bold text-gray-500 uppercase tracking-widest mb-3">Admin Tools</h4>
                  </div>

                  <Link href={`/leagues/${leagueId}/admin/settings`} className="w-full flex items-center justify-between p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:border-[#2A3A52] transition-colors mt-2">
                    <div className="flex items-center gap-3">
                      <Settings className="w-5 h-5 text-gray-400" />
                      <span className="font-medium text-gray-300">League Settings</span>
                    </div>
                  </Link>

                  <Link href={`/leagues/${leagueId}/admin/teams`} className="w-full flex items-center justify-between p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:border-[#2A3A52] transition-colors">
                    <div className="flex items-center gap-3">
                      <Users className="w-5 h-5 text-white" />
                      <span className="font-medium text-white">Manage Teams</span>
                    </div>
                  </Link>

                  <Link href={`/leagues/${leagueId}/admin/groups`} className="w-full flex items-center justify-between p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:border-[#2A3A52] transition-colors">
                    <div className="flex items-center gap-3">
                      <LayoutGrid className="w-5 h-5 text-white" />
                      <span className="font-medium text-white">Group Overview</span>
                    </div>
                  </Link>

                  <Link href={`/leagues/${leagueId}/admin/fixtures`} className="w-full flex items-center justify-between p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:border-[#2A3A52] transition-colors">
                    <div className="flex items-center gap-3">
                      <CalendarPlus className="w-5 h-5 text-white" />
                      <span className="font-medium text-white">Schedule Fixtures</span>
                    </div>
                  </Link>

                  <Link href={`/leagues/${leagueId}/admin/knockout-draw`} className="w-full flex items-center justify-between p-3 bg-[#0B1221] border border-[#1E293B] rounded-xl hover:border-[#2A3A52] transition-colors">
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
          )}
        </div>
      </div>
    </div>
  );
}
