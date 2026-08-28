'use client';

import { useState, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useMatches } from '@/hooks/useMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { MatchPosterModal } from '@/components/leagues/MatchPosterModal';
import { 
  ArrowLeft, Loader2, ShieldCheck, ImageIcon, PlayCircle, 
  Copy, Video, UploadCloud, Tag
} from 'lucide-react';
import { auth, db } from '@/lib/firebase';
import { doc, getDoc } from 'firebase/firestore';

export default function MatchDetailScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;
  const matchId = params.matchId as string;

  const { matches, loading: matchesLoading } = useMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  const [posterModalOpen, setPosterModalOpen] = useState(false);
  const [authUid, setAuthUid] = useState<string | null>(null);
  const [isTeamMember, setIsTeamMember] = useState(false);
  
  const match = matches.find(m => m.id === matchId);
  const homeTeam = teams.find(t => t.id === match?.homeTeamId);
  const awayTeam = teams.find(t => t.id === match?.awayTeamId);

  const isFinished = match?.status === 'completed' || match?.status === 'played' || match?.isPlayed;
  const hasScore = match?.homeScore != null && match?.awayScore != null;

  // ── Access Guards ──
  useEffect(() => {
    const unsub = auth.onAuthStateChanged(async (user) => {
      if (!user) {
        setAuthUid(null);
        return;
      }
      setAuthUid(user.uid);
      
      if (match) {
        try {
          const membershipDoc = await getDoc(doc(db, 'leagues', leagueId, 'memberships', user.uid));
          const teamId = membershipDoc.data()?.teamId;
          if (teamId === match.homeTeamId || teamId === match.awayTeamId) {
            setIsTeamMember(true);
          }
        } catch (e) {
          console.warn('Membership check failed:', e);
        }
      }
    });
    return () => unsub();
  }, [match, leagueId]);

  if (matchesLoading || teamsLoading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  if (!match) {
    return (
      <div className="text-center py-20 text-red-500 font-black text-xl">Match not found.</div>
    );
  }

  const handleCopyId = () => {
    navigator.clipboard.writeText(match.id!);
    alert('Live Match ID copied to clipboard!');
  };

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-16 px-2 sm:px-0">
      
      {/* ── HEADER ── */}
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl font-black text-white tracking-tight">Match Details</h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Round {match.roundNumber}</p>
        </div>
      </div>

      {/* ── SCOREBOARD BANNER ── */}
      <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 md:p-8 shadow-2xl relative overflow-hidden">
        {/* Background glow */}
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-64 h-64 bg-[#BEF264]/5 blur-[100px] rounded-full pointer-events-none" />
        
        <div className="flex items-center justify-between relative z-10">
          
          {/* Home Team */}
          <div className="flex-1 flex flex-col items-center gap-3">
            <div className="w-16 h-16 md:w-20 md:h-20 rounded-full bg-[#1E293B] border-2 border-white/10 flex items-center justify-center overflow-hidden shrink-0 shadow-lg">
              {homeTeam?.teamImageUrl ? <img src={homeTeam.teamImageUrl} className="w-full h-full object-cover" /> : <ShieldCheck className="w-8 h-8 text-gray-500" />}
            </div>
            <span className="text-base md:text-lg font-black text-white text-center leading-tight">
              {homeTeam?.name || 'TBD'}
            </span>
          </div>

          {/* Score Box */}
          <div className="shrink-0 flex flex-col items-center justify-center px-4 md:px-10">
            <span className={`px-3 py-1 rounded-md text-[10px] font-black uppercase tracking-widest mb-3 ${isFinished ? 'bg-gray-800 text-gray-400' : 'bg-red-500/20 text-red-500 animate-pulse'}`}>
              {isFinished ? 'Final' : 'Pending / Live'}
            </span>
            <div className="text-4xl md:text-5xl font-black tracking-widest text-white drop-shadow-md">
              {isFinished && hasScore ? `${match.homeScore} - ${match.awayScore}` : 'VS'}
            </div>
          </div>

          {/* Away Team */}
          <div className="flex-1 flex flex-col items-center gap-3">
            <div className="w-16 h-16 md:w-20 md:h-20 rounded-full bg-[#1E293B] border-2 border-white/10 flex items-center justify-center overflow-hidden shrink-0 shadow-lg">
              {awayTeam?.teamImageUrl ? <img src={awayTeam.teamImageUrl} className="w-full h-full object-cover" /> : <ShieldCheck className="w-8 h-8 text-gray-500" />}
            </div>
            <span className="text-base md:text-lg font-black text-white text-center leading-tight">
              {awayTeam?.name || 'TBD'}
            </span>
          </div>
        </div>
      </div>

      {/* ── ACTION CARDS GRID ── */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        
        {/* Match Poster Generation */}
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-full bg-[#BEF264]/10 flex items-center justify-center shrink-0">
              <ImageIcon className="w-6 h-6 text-[#BEF264]" />
            </div>
            <div>
              <h3 className="text-base font-black text-white">Match Poster</h3>
              <p className="text-xs text-gray-400 font-semibold mt-1">Generate a shareable promo card</p>
            </div>
          </div>
          <button onClick={() => setPosterModalOpen(true)} className="px-5 py-2.5 bg-[#BEF264] text-[#0F172A] text-xs font-black rounded-xl hover:brightness-110 shadow-lg shadow-[#BEF264]/10">
            Generate
          </button>
        </div>

        {/* Live Broadcast Section */}
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
          <h3 className="text-base font-black text-white flex items-center gap-2 mb-2">
            <PlayCircle className="w-5 h-5 text-red-500" /> Live Match
          </h3>
          <p className="text-xs text-gray-400 font-medium leading-relaxed mb-4">
            Host or join a live session to track goals, cards, and events in real-time.
          </p>
          
          <div className="flex items-center gap-3 bg-[#1E293B]/50 border border-[#1E293B] rounded-xl px-4 py-2.5 mb-4">
            <Tag className="w-4 h-4 text-gray-500" />
            <span className="flex-1 text-sm font-bold text-white tracking-widest truncate">{match.id}</span>
            <button onClick={handleCopyId} className="p-1.5 text-[#BEF264] hover:bg-[#BEF264]/10 rounded-lg transition-colors">
              <Copy className="w-4 h-4" />
            </button>
          </div>

          <button onClick={() => alert('Live Broadcast requires the mobile app engine.')} className="w-full py-3.5 bg-[#1E293B] hover:bg-[#2A3A52] text-white text-xs font-black rounded-xl transition-colors border border-white/5">
            OPEN HOST / LIVE VIEW
          </button>
        </div>

        {/* Highlights Section */}
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl md:col-span-2">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-base font-black text-white flex items-center gap-2">
              <Video className="w-5 h-5 text-sky-400" /> Highlights
            </h3>
            
            {/* Parity: Gating upload based on status and membership */}
            {isFinished && isTeamMember && (
              <button className="px-4 py-2 bg-sky-500/10 border border-sky-500/30 text-sky-400 text-xs font-black rounded-xl hover:bg-sky-500/20 transition-colors flex items-center gap-2">
                <UploadCloud className="w-4 h-4" /> Upload
              </button>
            )}
          </div>

          {!isFinished ? (
             <div className="py-8 bg-[#1E293B]/30 border border-[#1E293B] rounded-2xl text-center">
               <p className="text-sm font-bold text-gray-400">Highlights can be uploaded after the match is completed.</p>
             </div>
          ) : !isTeamMember ? (
             <div className="py-8 bg-[#1E293B]/30 border border-[#1E293B] rounded-2xl text-center">
               <p className="text-sm font-bold text-gray-400">Only home/away team members can upload highlights.</p>
             </div>
          ) : (
            <div className="py-8 bg-[#1E293B]/30 border border-[#1E293B] rounded-2xl text-center">
               <p className="text-sm font-bold text-gray-400">No highlights uploaded yet.</p>
             </div>
          )}
        </div>

      </div>

      {/* Match Poster Modal */}
      {posterModalOpen && (
        <MatchPosterModal
          leagueId={leagueId}
          matchId={matchId}
          onClose={() => setPosterModalOpen(false)}
        />
      )}
    </div>
  );
}
