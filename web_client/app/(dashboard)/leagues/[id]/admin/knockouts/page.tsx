'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useKnockoutMatches } from '@/hooks/useKnockoutMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Save, GitMerge, ShieldAlert } from 'lucide-react';
import { KnockoutMatch } from '@/types/match';
import { TournamentController } from '@/lib/algorithms/tournamentController';
import { saveKnockoutMatchesWeb } from '@/lib/leagues/leagueAdminRepository';

export default function AdminKnockoutScoreScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { matches, loading: matchesLoading } = useKnockoutMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  const [savingId, setSavingId] = useState<string | null>(null);

  if (matchesLoading || teamsLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" /></div>;

  const getTeamName = (teamId?: string) => {
    if (!teamId) return 'TBD';
    return teams.find(t => t.id === teamId)?.name || 'Unknown Team';
  };

  const handleUpdateScore = async (
    matchId: string, 
    homeScore: number, 
    awayScore: number, 
    homePen: number, 
    awayPen: number, 
    isFinal: boolean
  ) => {
    setSavingId(matchId);
    try {
      const match = matches.find(m => m.id === matchId);
      if (!match) throw new Error("Match not found");

      // Calculate winner
      let winnerId = null;
      if (homeScore > awayScore) winnerId = match.homeTeamId;
      else if (awayScore > homeScore) winnerId = match.awayTeamId;
      else if (homePen > awayPen) winnerId = match.homeTeamId;
      else if (awayPen > homePen) winnerId = match.awayTeamId;
      else {
        alert("Knockout matches cannot end in a pure draw. Please enter penalty scores to declare a winner.");
        setSavingId(null);
        return;
      }

      const payload: Partial<KnockoutMatch> = {
        ...match,
        homeScore,
        awayScore,
        homePenaltyScore: homePen > 0 || awayPen > 0 ? homePen : undefined,
        awayPenaltyScore: homePen > 0 || awayPen > 0 ? awayPen : undefined,
        status: 'completed',
        tiebreakWinnerTeamId: winnerId || undefined
      };

      // STRICT PARITY: Calculate the mathematical progression
      const advancedMatches = TournamentController.processMatchResult(payload, matches);
      
      // Batch save the updated tree to Firestore
      await saveKnockoutMatchesWeb(leagueId, advancedMatches);
      
      alert("Score updated and bracket advanced successfully!");
    } catch (error) {
      console.error("Failed to update score", error);
      alert("Failed to update score. Check permissions.");
    } finally {
      setSavingId(null);
    }
  };

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10 px-4 sm:px-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white flex items-center gap-3">
            <GitMerge className="w-6 h-6 text-[#BEF264]" />
            Knockout Score Editor
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Manage bracket progression and penalty shootouts.</p>
        </div>
      </div>

      <div className="space-y-4">
        {matches.length === 0 ? (
          <Glass className="p-10 text-center text-gray-400 flex flex-col items-center border border-[#1E293B]">
             <ShieldAlert className="w-12 h-12 mb-3 opacity-50 text-gray-600" />
             <p className="text-white font-black text-lg">No knockout matches found</p>
             <p className="text-sm mt-1">Generate the bracket from the admin dashboard first.</p>
          </Glass>
        ) : (
          matches.map((match) => (
             match.homeTeamId && match.awayTeamId ? (
                <KnockoutEditorRow 
                  key={match.id} 
                  match={match} 
                  homeTeamName={getTeamName(match.homeTeamId)}
                  awayTeamName={getTeamName(match.awayTeamId)}
                  isSaving={savingId === match.id}
                  onSave={handleUpdateScore}
                />
             ) : null
          ))
        )}
      </div>
    </div>
  );
}

function KnockoutEditorRow({ 
  match, homeTeamName, awayTeamName, isSaving, onSave 
}: { 
  match: KnockoutMatch, homeTeamName: string, awayTeamName: string, isSaving: boolean, onSave: any 
}) {
  const [hScore, setHScore] = useState(match.homeScore || 0);
  const [aScore, setAScore] = useState(match.awayScore || 0);
  const [hPen, setHPen] = useState(match.homePenaltyScore || 0);
  const [aPen, setAPen] = useState(match.awayPenaltyScore || 0);

  const isPlayed = match.status === 'played' || match.status === 'completed';

  return (
    <div className={`bg-[#0B1221] border border-[#1E293B] rounded-3xl p-5 shadow-xl transition-all border-l-4 ${isPlayed ? 'border-l-gray-600 opacity-70' : 'border-l-[#BEF264]'}`}>
      <div className="flex justify-between items-center mb-4">
        <span className="text-[10px] font-black uppercase tracking-widest text-gray-500 bg-[#1E293B] px-2.5 py-1 rounded-lg">
          {match.roundName}
        </span>
        <span className={`px-2.5 py-1 rounded-lg text-[10px] font-black uppercase tracking-widest ${isPlayed ? 'bg-[#BEF264]/10 text-[#BEF264]' : 'bg-[#1E293B] text-gray-400'}`}>
          {isPlayed ? 'Completed' : 'Pending'}
        </span>
      </div>

      <div className="flex flex-col md:flex-row items-center justify-between gap-6">
        <div className="flex items-center justify-center gap-4 w-full md:w-auto flex-1 bg-[#070B14] p-3 rounded-2xl border border-[#1E293B]">
          <div className="text-right flex-1 font-black text-white truncate text-sm">{homeTeamName}</div>
          <input type="number" min="0" value={hScore} onChange={(e) => setHScore(parseInt(e.target.value) || 0)} className="w-14 bg-[#1E293B] border border-white/10 rounded-xl p-2 text-center text-lg font-black text-white outline-none focus:border-[#BEF264]" />
          <span className="text-gray-600 font-black text-xl">:</span>
          <input type="number" min="0" value={aScore} onChange={(e) => setAScore(parseInt(e.target.value) || 0)} className="w-14 bg-[#1E293B] border border-white/10 rounded-xl p-2 text-center text-lg font-black text-white outline-none focus:border-[#BEF264]" />
          <div className="text-left flex-1 font-black text-white truncate text-sm">{awayTeamName}</div>
        </div>

        {(hScore === aScore) && (
          <div className="flex flex-col items-center justify-center gap-1 w-full md:w-auto bg-[#070B14] p-3 rounded-2xl border border-amber-500/30">
            <span className="text-[10px] uppercase font-black text-amber-500 tracking-widest">Penalties</span>
            <div className="flex items-center gap-2">
              <input type="number" min="0" value={hPen} onChange={(e) => setHPen(parseInt(e.target.value) || 0)} className="w-12 bg-amber-500/10 border border-amber-500/20 rounded-lg text-center text-sm font-black text-amber-500 focus:outline-none" />
              <span className="text-amber-500/50 font-black">-</span>
              <input type="number" min="0" value={aPen} onChange={(e) => setAPen(parseInt(e.target.value) || 0)} className="w-12 bg-amber-500/10 border border-amber-500/20 rounded-lg text-center text-sm font-black text-amber-500 focus:outline-none" />
            </div>
          </div>
        )}

        <div className="flex items-center gap-2 w-full md:w-auto shrink-0">
          <button onClick={() => onSave(match.id, hScore, aScore, hPen, aPen, true)} disabled={isSaving} className="w-full md:w-auto px-6 py-4 bg-[#BEF264] text-[#0F172A] hover:brightness-110 rounded-xl text-xs font-black flex items-center justify-center gap-2 shadow-lg disabled:opacity-50">
            {isSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
            {isPlayed ? 'UPDATE SCORE' : 'SAVE SCORE'}
          </button>
        </div>
      </div>
    </div>
  );
}
