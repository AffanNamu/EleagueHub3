/*components/league/LeagueDetailScreenClient.tsx*/

import { useState, useEffect } from 'react';
import { useRouter, useParams } from 'next/navigation';
import { motion } from 'framer-motion';
import { 
  ArrowLeft, RefreshCw, Trophy, Shield, Globe, 
  MessageCircle, LayoutGrid, Calendar, Medal, Lock, 
  Mic, Settings, Network, ChevronRight, Gift, ArrowRight 
} from 'lucide-react';
import { auth } from '@/lib/firebase';
import { fetchFullLeagueDetails, FullLeagueDetails, LeagueFetchError } from '@/lib/leagues/leagueDetailsRepository';

export default function LeagueDetailScreenClient() {
  const router = useRouter();
  const params = useParams() as { id: string };
  const leagueId = params?.id;

  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<FullLeagueDetails | null>(null);
  const [authUid, setAuthUid] = useState<string | null>(null);
  const [spaceLive, setSpaceLive] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

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
      if (details.partialErrors.length > 0) {
        // Non-fatal: the league loaded, but some sections (teams, fixtures,
        // knockouts, announcements, or membership) failed to read. Surface
        // it in the console loudly rather than hiding it, per project rules.
        console.warn('[LeagueDetailScreenClient] Partial load errors:', details.partialErrors);
      }
    } catch (err) {
      console.error('Failed to load league details:', err);
      if (err instanceof LeagueFetchError) {
        setErrorMsg(err.message);
      } else if (err instanceof Error) {
        setErrorMsg(`A network error occurred while fetching the league: ${err.message}`);
      } else {
        setErrorMsg('An unknown error occurred while fetching the league.');
      }
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

  if (loading) {
    return (
      <div className="min-h-screen bg-[#081120] flex items-center justify-center">
        <div className="w-12 h-12 border-4 border-brand-lime border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (errorMsg || !data?.league) {
    return (
      <div className="min-h-screen bg-[#081120] flex flex-col items-center justify-center p-6 text-center">
        <Shield className="w-16 h-16 text-red-500 mb-4" />
        <h2 className="text-xl font-black text-white mb-2">Failed to load</h2>
        <p className="text-sm text-slate-400 mb-6 max-w-md">{errorMsg || 'Unknown error occurred.'}</p>
        <div className="flex gap-3">
          <button 
            onClick={loadData}
            className="px-6 py-3 bg-white/10 text-white font-black rounded-xl hover:bg-white/20 transition-all"
          >
            Retry
          </button>
          <button 
            onClick={() => router.push('/leagues')}
            className="px-6 py-3 bg-brand-lime text-slate-900 font-black rounded-xl hover:brightness-110 transition-all"
          >
            Go Back
          </button>
        </div>
      </div>
    );
  }

  const league = data.league;
  const isOwner = data.isOwner ?? false;
  const isJoined = data.isJoined ?? false;
  const teams = data.teams || {};
  const fixtures = data.fixtures || [];
  const announcements = data.announcements || [];
  
  const unplayedFixtures = fixtures.filter(f => f?.status === 'scheduled');
  const upcomingMatches = unplayedFixtures.slice(0, 3);

  // Safe Inline Formatting Helpers
  const getFormatLabel = (fmt: any) => {
    if (fmt === 3 || fmt === 'worldCup') return 'World Cup';
    if (fmt === 1 || fmt === 'uclGroup') return 'Group Stage';
    if (fmt === 2 || fmt === 'uclSwiss') return 'Swiss Series';
    return 'Classic League';
  };

  const getCategoryLabel = (cat: any) => {
    if (cat === 1 || cat === 'eFootball') return 'eFootball';
    if (cat === 2 || cat === 'eaSportsFc') return 'EA SPORTS FC';
    if (cat === 3 || cat === 'eaSportsFcMobile') return 'FC Mobile';
    if (cat === 4 || cat === 'dreamLeagueSoccer') return 'Dream League Soccer';
    if (cat === 5 || cat === 'totalFootball') return 'Total Football';
    return 'Local Football';
  };

  return (
    <div className="min-h-screen bg-[#081120] text-white font-sans selection:bg-brand-lime selection:text-slate-900 pb-20">
      <header className="sticky top-0 z-50 bg-[#081120]/80 backdrop-blur-md border-b border-white/5 px-4 h-16 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => router.push('/leagues')} className="w-10 h-10 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-slate-300 transition-colors">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-black tracking-tight truncate max-w-[200px] md:max-w-md">
            {league?.name || 'League Details'}
          </h1>
        </div>
        <button onClick={loadData} className="w-10 h-10 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 text-brand-lime transition-colors">
          <RefreshCw className="w-4 h-4" />
        </button>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 mt-6 flex flex-col lg:flex-row gap-6 items-start">
        <div className="flex-1 w-full space-y-6">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="relative w-full h-48 md:h-64 rounded-3xl overflow-hidden border border-white/10 bg-slate-900 group">
            {league?.leagueImageUrl ? (
              <img src={league.leagueImageUrl} alt="League Cover" className="w-full h-full object-cover opacity-60 group-hover:opacity-80 transition-opacity duration-500" />
            ) : (
              <div className="w-full h-full flex items-center justify-center bg-slate-800">
                <Trophy className="w-16 h-16 text-white/10" />
              </div>
            )}
            <div className="absolute inset-0 bg-gradient-to-t from-[#081120] via-transparent to-transparent" />
            {league?.sponsorImageUrl && (
              <div className="absolute bottom-4 right-4 w-16 h-16 bg-white/90 backdrop-blur-sm p-2 rounded-xl border border-white/20 shadow-2xl flex items-center justify-center">
                <img src={league.sponsorImageUrl} alt="Sponsor" className="max-w-full max-h-full object-contain" />
              </div>
            )}
          </motion.div>

          {!isJoined && (
            <GlassCard>
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-full bg-brand-lime/10 flex items-center justify-center shrink-0">
                  <Lock className="w-6 h-6 text-brand-lime" />
                </div>
                <div className="flex-1">
                  <h3 className="text-lg font-black text-white">Join This League</h3>
                  <p className="text-xs text-slate-400 font-medium mt-1">You are viewing this as a guest. Join to compete or track your stats.</p>
                </div>
              </div>
              <button className="w-full mt-5 py-3.5 bg-brand-lime text-slate-900 font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2">
                Join Now <ArrowRight className="w-4 h-4" />
              </button>
            </GlassCard>
          )}

          <GlassCard>
            <div className="flex items-center justify-between mb-6">
              <h3 className="text-lg font-black text-white flex items-center gap-2">
                <Calendar className="w-5 h-5 text-brand-lime" /> Upcoming Matches
              </h3>
              <button onClick={() => router.push(`/leagues/${leagueId}/fixtures`)} className="text-xs font-bold text-brand-lime hover:text-white transition-colors flex items-center gap-1">
                View All <ChevronRight className="w-4 h-4" />
              </button>
            </div>
            {upcomingMatches.length === 0 ? (
              <div className="py-6 text-center text-sm font-semibold text-slate-500">
                No upcoming fixtures available.
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {upcomingMatches.map((match) => (
                  <MatchRow key={match.id} homeTeam={teams[match.homeTeamId]} awayTeam={teams[match.awayTeamId]} round={`R${match.roundNumber || 0}`} />
                ))}
              </div>
            )}
          </GlassCard>

          {announcements.length > 0 && (
            <GlassCard>
              <h3 className="text-lg font-black text-white flex items-center gap-2 mb-4">
                <MessageCircle className="w-5 h-5 text-sky-400" /> Announcements
              </h3>
              <div className="space-y-3">
                {announcements.map((ann) => (
                  <div key={ann.id} className="p-4 rounded-xl bg-sky-500/10 border border-sky-500/20">
                    <h4 className="text-sm font-bold text-sky-100 mb-1">{ann.title || 'Announcement'}</h4>
                    <p className="text-xs font-semibold text-sky-200/80">{ann.message}</p>
                  </div>
                ))}
              </div>
            </GlassCard>
          )}
        </div>

        <div className="w-full lg:w-[380px] space-y-6 lg:sticky lg:top-24">
          <GlassCard>
            <h2 className="text-xl font-black text-white mb-2">{league?.name}</h2>
            <p className="text-sm text-slate-400 font-medium leading-relaxed mb-6">
              {league?.description || 'No description provided for this competition.'}
            </p>
            <div className="flex flex-wrap gap-2 mb-6">
              <Badge color="lime" label={league?.privacy === 'private' ? 'Private' : 'Public'} />
              <Badge color="amber" label={`${Object.keys(teams).length} / ${league?.maxTeams || 0} Teams`} />
              <Badge color="violet" label={getCategoryLabel(league?.footballCategory)} />
              <Badge color="sky" label={getFormatLabel(league?.format)} />
            </div>
            <div className="h-px w-full bg-white/10 my-6" />
            <button className={`w-full py-4 rounded-xl border flex items-center justify-center gap-3 transition-all ${spaceLive ? 'bg-red-500/10 border-red-500/30 text-red-500 hover:bg-red-500/20' : 'bg-brand-lime/10 border-brand-lime/30 text-brand-lime hover:bg-brand-lime/20'}`}>
              <Mic className="w-5 h-5" />
              <span className="font-black tracking-wide">{spaceLive ? 'JOIN LIVE SPACE' : 'START AUDIO SPACE'}</span>
            </button>
          </GlassCard>

          <div className="grid grid-cols-2 gap-3">
            <BentoButton icon={LayoutGrid} label="Fixtures" onClick={() => router.push(`/leagues/${leagueId}/fixtures`)} />
            <BentoButton icon={Trophy} label="Standings" onClick={() => router.push(`/leagues/${leagueId}/standings`)} />
            <BentoButton icon={Network} label="Knockouts" onClick={() => router.push(`/leagues/${leagueId}/knockout`)} />
            <BentoButton icon={MessageCircle} label="Chatroom" onClick={() => router.push(`/leagues/${leagueId}/chat`)} />
          </div>

          {isOwner && (
            <GlassCard>
              <h3 className="text-xs font-black uppercase tracking-widest text-slate-500 mb-4 flex items-center gap-2">
                <Shield className="w-4 h-4" /> Organizer Tools
              </h3>
              <div className="space-y-3">
                <AdminButton icon={Medal} label="Manage Scores" onClick={() => router.push(`/leagues/${leagueId}/admin-scores`)} />
                <AdminButton icon={Settings} label="League Settings" onClick={() => router.push(`/leagues/${leagueId}/admin`)} />
              </div>
            </GlassCard>
          )}
        </div>
      </main>
    </div>

  );
}

function GlassCard({ children }: { children: React.ReactNode }) {
  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="bg-[#0F172A] border border-white/5 rounded-3xl p-6 shadow-xl">
      {children}
    </motion.div>
  );
}

function Badge({ label, color, icon: Icon }: { label: string, color: 'lime' | 'amber' | 'violet' | 'sky', icon?: any }) {
  const colorMap = {
    lime: 'bg-brand-lime/10 border-brand-lime/20 text-brand-lime',
    amber: 'bg-amber-500/10 border-amber-500/20 text-amber-500',
    violet: 'bg-violet-500/10 border-violet-500/20 text-violet-400',
    sky: 'bg-sky-500/10 border-sky-500/20 text-sky-400',
  };
  return (
    <span className={`px-3 py-1.5 rounded-lg border text-xs font-black tracking-wide flex items-center gap-1.5 ${colorMap[color]}`}>
      {Icon && <Icon className="w-3.5 h-3.5" />}
      {label}
    </span>
  );
}

function BentoButton({ icon: Icon, label, onClick }: { icon: any, label: string, onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex flex-col items-center justify-center gap-3 p-5 rounded-2xl bg-[#0F172A] border border-white/5 hover:border-brand-lime/30 hover:bg-white/[0.02] transition-all group">
      <Icon className="w-6 h-6 text-slate-400 group-hover:text-brand-lime transition-colors" />
      <span className="text-xs font-black text-white tracking-wide">{label}</span>
    </button>
  );
}

function AdminButton({ icon: Icon, label, onClick }: { icon: any, label: string, onClick: () => void }) {
  return (
    <button onClick={onClick} className="w-full flex items-center gap-3 p-4 rounded-xl bg-white/[0.02] border border-white/5 hover:bg-white/[0.05] transition-colors text-left">
      <Icon className="w-5 h-5 text-brand-lime" />
      <span className="text-sm font-bold text-white">{label}</span>
      <ChevronRight className="w-4 h-4 text-slate-500 ml-auto" />
    </button>
  );
}

function MatchRow({ homeTeam, awayTeam, round }: { homeTeam?: any, awayTeam?: any, round: string }) {
  const homeName = homeTeam?.name || 'TBD';
  const awayName = awayTeam?.name || 'TBD';
  const homeLogo = homeTeam?.teamImageUrl;
  const awayLogo = awayTeam?.teamImageUrl;

  return (
    <div className="flex items-center justify-between p-4 rounded-xl bg-white/[0.02] border border-white/5 hover:bg-white/[0.04] transition-colors cursor-pointer">
      <div className="flex items-center gap-3 w-[40%]">
        <div className="w-8 h-8 rounded-full bg-slate-800 border border-white/10 flex items-center justify-center shrink-0 overflow-hidden">
          {homeLogo ? <img src={homeLogo} className="w-full h-full object-cover" /> : <Shield className="w-4 h-4 text-slate-400" />}
        </div>
        <span className="text-sm font-bold text-white truncate">{homeName}</span>
      </div>
      <div className="flex flex-col items-center justify-center px-2">
        <span className="text-[10px] font-black text-brand-lime bg-brand-lime/10 px-2 py-0.5 rounded">{round}</span>
        <span className="text-[10px] font-bold text-slate-500 mt-1">Pending</span>
      </div>
      <div className="flex items-center justify-end gap-3 w-[40%]">
        <span className="text-sm font-bold text-white truncate">{awayName}</span>
        <div className="w-8 h-8 rounded-full bg-slate-800 border border-white/10 flex items-center justify-center shrink-0 overflow-hidden">
          {awayLogo ? <img src={awayLogo} className="w-full h-full object-cover" /> : <Shield className="w-4 h-4 text-slate-400" />}
        </div>
      </div>
    </div>
  );
}
