'use client';

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { motion } from 'framer-motion';
import { 
  ArrowLeft, RefreshCw, Trophy, ShieldCheck, Globe, 
  MessageCircle, LayoutGrid, Calendar, Medal, Lock, 
  Mic, Settings, Network, ChevronRight, LogIn, Users,
  ListAlt, GitMerge, Edit, MicOff, SquareSquare
} from 'lucide-react';
import { auth, db } from '@/lib/firebase';
import { doc, setDoc, arrayUnion } from 'firebase/firestore';
import { fetchFullLeagueDetails, FullLeagueDetails } from '@/lib/leagues/leagueDetailsRepository';
import { leagueFormatDisplayName } from '@/lib/models/leagueFormat';
import { categoryLabel } from '@/lib/models/footballCategory';

export default function LeagueDetailScreenClient() {
  const router = useRouter();
  const params = useParams() as { id: string };
  const leagueId = params?.id;

  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<FullLeagueDetails | null>(null);
  const [authUid, setAuthUid] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  
  // UI State
  const [joining, setJoining] = useState(false);
  const [joinModalOpen, setJoinModalOpen] = useState(false);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged((user) => {
      if (!user) router.push('/login');
      else setAuthUid(user.uid);
    });
    return () => unsubscribe();
  }, [router]);

  const loadData = async () => {
    if (!authUid || !leagueId) return;
    setLoading(true);
    setErrorMsg(null);
    try {
      const details = await fetchFullLeagueDetails(leagueId, authUid);
      setData(details);
    } catch (err) {
      console.error('Failed to load league details:', err);
      setErrorMsg('An error occurred while fetching the league.');
      setData(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (authUid && leagueId) {
      loadData();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authUid, leagueId]);

  // ── Join Logic (Participant vs Viewer) ──
  const handleJoinDirect = async (role: 'participant' | 'viewer') => {
    if (!authUid || !leagueId || joining) return;
    setJoining(true);
    try {
      const leagueRef = doc(db, 'leagues', leagueId);
      const membershipRef = doc(db, 'leagues', leagueId, 'memberships', authUid);

      // Add to memberIds array
      await setDoc(leagueRef, {
        memberIds: arrayUnion(authUid),
        updatedAtMs: Date.now()
      }, { merge: true });

      // If participant, create membership doc (Role 1 = Member in Flutter enum)
      if (role === 'participant') {
        await setDoc(membershipRef, {
          id: authUid,
          leagueId: leagueId,
          userId: authUid,
          teamId: null,
          role: 1, 
          updatedAtMs: Date.now(),
          version: 1
        }, { merge: true });
      }

      setJoinModalOpen(false);
      await loadData();
    } catch (err) {
      console.error('Failed to join league:', err);
      alert('Failed to join league. Please try again.');
    } finally {
      setJoining(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-[#070B14] flex items-center justify-center">
        <div className="w-12 h-12 border-4 border-[#BEF264] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (errorMsg || !data?.league) {
    return (
      <div className="min-h-screen bg-[#070B14] flex flex-col items-center justify-center p-6 text-center">
        <ShieldCheck className="w-16 h-16 text-red-500 mb-4" />
        <h2 className="text-xl font-black text-white mb-2">Failed to load</h2>
        <p className="text-sm text-slate-400 mb-6">{errorMsg || 'Unknown error occurred.'}</p>
        <button onClick={() => router.push('/leagues')} className="px-6 py-3 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 transition-all">
          Go Back
        </button>
      </div>
    );
  }

  const league = data.league;
  const isOwner = data.isOwner ?? false;
  const isJoined = data.isJoined ?? false;
  const teams = data.teams || {};
  const fixtures = data.fixtures || [];
  const announcements = data.announcements || [];
  const space = data.space || null;
  const spaceLive = space?.isLive === true;
  const knockouts = data.knockouts || [];
  const hasKnockouts = knockouts.length > 0;
  
  const unplayedFixtures = fixtures.filter(f => !f.isPlayed);
  const upcomingMatches = unplayedFixtures.slice(0, 5); // Show top 5 upcoming

  const isSwiss = league.format === 'uclSwiss' || league.format === 2;
  const isGroup = league.format === 'uclGroup' || league.format === 1;
  const isWorldCup = league.format === 'worldCup' || league.format === 3;

  return (
    <div className="min-h-screen bg-[#070B14] text-white font-sans pb-20">
      <header className="sticky top-0 z-40 bg-[#070B14]/90 backdrop-blur-md border-b border-[#1E293B] px-4 md:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button onClick={() => router.push('/leagues')} className="w-10 h-10 flex items-center justify-center rounded-full bg-[#1E293B]/50 hover:bg-[#1E293B] text-white transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-black tracking-tight">League Details</h1>
        </div>
        <button onClick={loadData} className="w-10 h-10 flex items-center justify-center rounded-full bg-[#1E293B]/50 hover:bg-[#1E293B] text-[#BEF264] transition-colors">
          <RefreshCw className="w-4 h-4" />
        </button>
      </header>

      <main className="max-w-7xl mx-auto px-4 md:px-8 mt-6 flex flex-col lg:flex-row gap-6 items-start">
        
        {/* ── LEFT COLUMN (Main Content) ── */}
        <div className="flex-1 w-full space-y-6">
          
          {/* Overview Hero Card */}
          <GlassCard className="p-0 overflow-hidden">
            <div className="relative w-full h-48 md:h-64 bg-slate-900 group">
              {league.leagueImageUrl ? (
                <img src={league.leagueImageUrl} alt="League Cover" className="w-full h-full object-cover opacity-60 group-hover:opacity-80 transition-opacity duration-500" />
              ) : (
                <div className="w-full h-full flex items-center justify-center bg-[#0B1221]">
                  <Trophy className="w-16 h-16 text-white/5" />
                </div>
              )}
              <div className="absolute inset-0 bg-gradient-to-t from-[#0B1221] via-[#0B1221]/40 to-transparent" />
              
              {league.sponsorImageUrl && (
                <div className="absolute bottom-4 right-4 w-16 h-16 bg-white/90 backdrop-blur-sm p-2 rounded-xl border border-white/20 shadow-2xl flex items-center justify-center">
                  <img src={league.sponsorImageUrl} alt="Sponsor" className="max-w-full max-h-full object-contain" />
                </div>
              )}
            </div>

            <div className="p-6 md:p-8 bg-[#0B1221]">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <h2 className="text-2xl md:text-3xl font-black text-white tracking-tight truncate">{league.name}</h2>
                  <p className="text-sm font-bold text-gray-400 mt-1">
                    {leagueFormatDisplayName(league.format)} • {league.season}
                  </p>
                </div>
                {isOwner && (
                  <div className="w-10 h-10 rounded-full bg-[#BEF264]/10 border border-[#BEF264]/20 flex items-center justify-center shrink-0" title="Organizer">
                    <ShieldCheck className="w-5 h-5 text-[#BEF264]" />
                  </div>
                )}
              </div>

              {league.description && (
                <p className="text-sm text-gray-400 font-medium leading-relaxed mt-4">
                  {league.description}
                </p>
              )}

              {/* Dynamic Rule Pills (Parity with Flutter) */}
              <div className="flex flex-wrap gap-2 mt-6">
                <Pill label={league.privacy === 'private' ? 'Private' : 'Public'} color="lime" />
                <Pill label={`${league.maxTeams} Teams Max`} color="amber" />
                <Pill label={league.region || 'Global'} color="violet" />
                {(league.viewerCapacity || 0) > 0 && <Pill label={`${league.viewerCapacity} Viewers`} color="teal" />}
                <Pill label={league.settings?.doubleRoundRobin ? 'Double Round Robin' : 'Single Round Robin'} color="sky" />
                <Pill label={categoryLabel(league.footballCategory)} color="lime" />
                
                {isGroup && <Pill label={`Group Size: ${league.settings?.groupSize || 4}`} color="teal" />}
                {isSwiss && <Pill label={`Swiss Rounds: ${league.settings?.swissRounds || 5}`} color="teal" />}
                {isWorldCup && (
                  <Pill label={league.worldCupFormat === 'fifa2026' || league.worldCupFormat === 1 ? 'FIFA 2026 • 48 Teams' : 'FIFA 2022 • 32 Teams'} color="amber" />
                )}
              </div>

              {/* Master League Workspace Link */}
              {league.isInsideMasterLeague && league.masterLeagueId && (
                <div className="mt-6 pt-6 border-t border-[#1E293B] flex items-center gap-4">
                  <Pill label="Master League Competition" color="amber" />
                  <button onClick={() => router.push(`/master-leagues/${league.masterLeagueId}`)} className="text-sm font-bold text-white flex items-center gap-2 hover:text-[#BEF264] transition-colors">
                    <Network className="w-4 h-4" /> Open Workspace
                  </button>
                </div>
              )}
            </div>
          </GlassCard>

          {/* Join League Card */}
          {!isJoined && (
            <GlassCard className="p-6">
              <div className="flex items-center gap-3 mb-2">
                <LogIn className="w-6 h-6 text-[#BEF264]" />
                <h3 className="text-xl font-black text-white">Join This League</h3>
              </div>
              <p className="text-sm text-gray-400 mb-6 font-medium">
                {league.isInsideMasterLeague 
                  ? 'This competition belongs to a master league workspace. Join now as participant or viewer.' 
                  : 'You have not joined this league yet. Join now as participant or add it to your list as viewer.'}
              </p>
              <button 
                onClick={() => setJoinModalOpen(true)}
                className="w-full py-3.5 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2 shadow-lg shadow-[#BEF264]/10"
              >
                <LogIn className="w-5 h-5" /> Join League
              </button>
            </GlassCard>
          )}

          {/* Announcements Card */}
          {announcements.length > 0 && (
            <GlassCard className="p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-black text-white flex items-center gap-2">
                  <MessageCircle className="w-5 h-5 text-sky-400" /> Announcements
                </h3>
              </div>
              <div className="flex gap-4 overflow-x-auto pb-2 custom-scrollbar">
                {announcements.map((ann) => (
                  <div key={ann.id} className="min-w-[280px] p-5 rounded-2xl bg-[#0B1221] border border-[#1E293B] shrink-0">
                    <h4 className="text-sm font-black text-white mb-2">{ann.title || 'Announcement'}</h4>
                    <p className="text-xs font-semibold text-gray-400 leading-relaxed line-clamp-3">{ann.message}</p>
                    <span className="text-[10px] font-bold text-gray-500 mt-4 block">
                      {new Date(ann.createdAtMs || Date.now()).toLocaleDateString()}
                    </span>
                  </div>
                ))}
              </div>
            </GlassCard>
          )}

          {/* Upcoming Matches */}
          <GlassCard className="p-6">
            <h3 className="text-lg font-black text-white flex items-center gap-2 mb-6">
              <Calendar className="w-5 h-5 text-[#BEF264]" /> Coming Up Next
            </h3>
            
            {upcomingMatches.length === 0 ? (
              <div className="py-10 text-center text-sm font-semibold text-gray-500">
                No upcoming fixtures scheduled yet.
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {upcomingMatches.map((match) => (
                  <div key={match.id} onClick={() => router.push(`/leagues/${leagueId}/matches/${match.id}`)} className="flex items-center justify-between p-4 rounded-xl bg-[#0B1221] border border-[#1E293B] hover:border-white/10 transition-colors cursor-pointer group">
                    <div className="bg-[#1E293B] px-3 py-1.5 rounded-lg text-xs font-black text-gray-400">
                      R{match.roundNumber}
                    </div>
                    
                    <div className="flex-1 flex items-center justify-end gap-3 px-4">
                      <span className="text-sm font-bold text-white truncate max-w-[120px]">{teams[match.homeTeamId]?.name || 'TBD'}</span>
                      <TeamThumb url={teams[match.homeTeamId]?.teamImageUrl} />
                    </div>
                    
                    <span className="text-xs font-black text-[#BEF264] px-2">VS</span>
                    
                    <div className="flex-1 flex items-center justify-start gap-3 px-4">
                      <TeamThumb url={teams[match.awayTeamId]?.teamImageUrl} />
                      <span className="text-sm font-bold text-white truncate max-w-[120px]">{teams[match.awayTeamId]?.name || 'TBD'}</span>
                    </div>

                    <ChevronRight className="w-5 h-5 text-gray-500 group-hover:text-white transition-colors" />
                  </div>
                ))}
                <button onClick={() => router.push(`/leagues/${leagueId}/fixtures`)} className="mt-4 text-xs font-black text-[#BEF264] hover:text-white transition-colors w-full text-center py-2">
                  View all fixtures
                </button>
              </div>
            )}
          </GlassCard>
        </div>

        {/* ── RIGHT COLUMN (Sidebar / Quick Actions) ── */}
        <div className="w-full lg:w-[380px] space-y-6 lg:sticky lg:top-24">
          
          <GlassCard className="p-6">
            <h3 className="text-base font-black text-white mb-4">Quick Actions</h3>
            
            {/* Space Row */}
            <div className="flex gap-2 mb-4">
              <button className="flex-1 py-3.5 bg-[#0B1221] border border-[#1E293B] text-[#BEF264] hover:bg-[#1E293B] font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors">
                {spaceLive ? <Mic className="w-4 h-4" /> : <MicOff className="w-4 h-4" />}
                {spaceLive ? 'Join Live Space' : 'Audio Space'}
              </button>
              {isOwner && (
                <button className="flex-1 py-3.5 bg-[#BEF264] text-[#0F172A] hover:brightness-110 font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-all">
                  <Mic className="w-4 h-4" /> Start Space
                </button>
              )}
            </div>

            <button onClick={() => router.push(`/leagues/${leagueId}/chat`)} className="w-full mb-6 py-3.5 bg-[#0B1221] border border-[#1E293B] text-[#BEF264] hover:bg-[#1E293B] font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors">
              <MessageCircle className="w-4 h-4" /> League Chatroom
            </button>

            {/* Standard Data Links */}
            <div className="grid grid-cols-2 gap-3 mb-4">
              <BentoButton icon={ListAlt} label="Fixtures" onClick={() => router.push(`/leagues/${leagueId}/fixtures`)} />
              <BentoButton icon={Trophy} label="Standings" onClick={() => router.push(`/leagues/${leagueId}/standings`)} />
            </div>

            {/* Knockout Guard Logic */}
            {!isOwner && (
              hasKnockouts ? (
                <button onClick={() => router.push(`/leagues/${leagueId}/knockout`)} className="w-full py-3.5 bg-[#BEF264] text-[#0F172A] font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-all">
                  <Trophy className="w-4 h-4" /> View Knockout Bracket
                </button>
              ) : (
                <div className="w-full py-3.5 bg-[#0B1221] border border-[#1E293B] text-gray-500 font-bold text-xs rounded-xl text-center">
                  Knockouts not generated yet
                </div>
              )
            )}

            {/* Admin Tools */}
            {isOwner && (
              <div className="mt-6 pt-6 border-t border-[#1E293B] space-y-2">
                <button onClick={() => router.push(`/leagues/${leagueId}/admin-scores`)} className="w-full py-4 bg-[#BEF264] text-[#0F172A] font-black text-sm rounded-xl flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#BEF264]/10">
                  <Edit className="w-4 h-4" /> Manage League Scores
                </button>
                <button onClick={() => router.push(`/leagues/${leagueId}/admin`)} className="w-full py-3.5 bg-[#0B1221] border border-[#1E293B] text-[#BEF264] hover:bg-[#1E293B] font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors">
                  <Settings className="w-4 h-4" /> League Settings
                </button>

                {/* Swiss / Group / World Cup Knockout Generators */}
                {isSwiss && (
                  <button onClick={() => alert('Swiss knockout generation triggered.')} className="w-full mt-2 py-3.5 border border-[#BEF264]/50 text-[#BEF264] bg-[#BEF264]/5 hover:bg-[#BEF264]/10 font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors">
                    <Trophy className="w-4 h-4" /> Generate Swiss Knockouts
                  </button>
                )}
                {isGroup && (
                  <button onClick={() => alert('Group knockout generation triggered.')} className="w-full mt-2 py-3.5 border border-[#BEF264]/50 text-[#BEF264] bg-[#BEF264]/5 hover:bg-[#BEF264]/10 font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors">
                    <LayoutGrid className="w-4 h-4" /> Generate Group Knockouts
                  </button>
                )}
                {isWorldCup && (
                  <button onClick={() => alert('World Cup knockout generation triggered.')} className="w-full mt-2 py-3.5 border border-[#BEF264]/50 text-[#BEF264] bg-[#BEF264]/5 hover:bg-[#BEF264]/10 font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors">
                    <Globe className="w-4 h-4" /> Generate World Cup Knockouts
                  </button>
                )}

                {/* Admin Knockout Viewing */}
                {(isSwiss || isGroup || isWorldCup) && (
                  <div className="flex gap-2 mt-4">
                    <button onClick={() => hasKnockouts ? router.push(`/leagues/${leagueId}/knockout`) : alert('Need knockouts first')} className={`flex-1 py-3 border font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors ${hasKnockouts ? 'border-[#1E293B] bg-[#0B1221] text-[#BEF264] hover:bg-[#1E293B]' : 'border-transparent bg-[#0B1221] text-gray-500'}`}>
                      <GitMerge className="w-4 h-4" /> View Bracket
                    </button>
                    <button onClick={() => hasKnockouts ? router.push(`/leagues/${leagueId}/knockout-admin`) : alert('Need knockouts first')} className={`flex-1 py-3 border font-black text-xs rounded-xl flex items-center justify-center gap-2 transition-colors ${hasKnockouts ? 'border-[#1E293B] bg-[#0B1221] text-[#BEF264] hover:bg-[#1E293B]' : 'border-transparent bg-[#0B1221] text-gray-500'}`}>
                      <Medal className="w-4 h-4" /> Manage KO Scores
                    </button>
                  </div>
                )}
              </div>
            )}
          </GlassCard>
        </div>
      </main>

      {/* Join Modal */}
      {joinModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-sm bg-[#0B1221] rounded-3xl shadow-2xl p-6 text-center border border-[#1E293B]">
            <h3 className="text-xl font-black text-white mb-2">Join League</h3>
            <p className="text-sm text-gray-400 font-medium mb-6">Choose how you want to join this competition.</p>
            <div className="flex flex-col gap-3">
              <button disabled={joining} onClick={() => handleJoinDirect('participant')} className="w-full py-3.5 rounded-xl bg-[#BEF264] text-[#0F172A] text-sm font-black hover:brightness-110 transition-all disabled:opacity-50">
                {joining ? 'Joining...' : 'Join as Participant'}
              </button>
              <button disabled={joining} onClick={() => handleJoinDirect('viewer')} className="w-full py-3.5 rounded-xl border border-[#1E293B] text-white text-sm font-bold hover:bg-[#1E293B] transition-colors disabled:opacity-50">
                Join as Viewer
              </button>
              <button disabled={joining} onClick={() => setJoinModalOpen(false)} className="w-full py-2 mt-2 text-sm font-bold text-gray-500 hover:text-white transition-colors disabled:opacity-50">
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Components ──

function GlassCard({ children, className = '' }: { children: React.ReactNode, className?: string }) {
  return (
    <div className={`bg-[#0B1221] border border-[#1E293B] rounded-3xl shadow-xl ${className}`}>
      {children}
    </div>
  );
}

function Pill({ label, color }: { label: string, color: 'lime' | 'amber' | 'violet' | 'sky' | 'teal' }) {
  const colorMap = {
    lime: 'bg-[#BEF264]/10 border-[#BEF264]/20 text-[#BEF264]',
    amber: 'bg-amber-500/10 border-amber-500/20 text-amber-500',
    violet: 'bg-violet-500/10 border-violet-500/20 text-violet-400',
    sky: 'bg-sky-500/10 border-sky-500/20 text-sky-400',
    teal: 'bg-teal-500/10 border-teal-500/20 text-teal-400',
  };
  return (
    <span className={`px-3 py-1.5 rounded-lg border text-[11px] font-black tracking-wide ${colorMap[color]}`}>
      {label}
    </span>
  );
}

function BentoButton({ icon: Icon, label, onClick }: { icon: any, label: string, onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex flex-col items-center justify-center gap-3 py-5 rounded-2xl bg-[#0B1221] border border-[#1E293B] hover:border-[#BEF264]/50 hover:bg-[#1E293B] transition-all group">
      <Icon className="w-6 h-6 text-[#BEF264]" />
      <span className="text-xs font-bold text-white tracking-wide">{label}</span>
    </button>
  );
}

function TeamThumb({ url }: { url?: string }) {
  return (
    <div className="w-8 h-8 rounded-full bg-slate-800 border border-white/10 flex items-center justify-center shrink-0 overflow-hidden">
      {url ? <img src={url} className="w-full h-full object-cover" /> : <ShieldCheck className="w-4 h-4 text-slate-500" />}
    </div>
  );
}
