'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { useKnockoutMatches } from '@/hooks/useKnockoutMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Save, GitMerge, ShieldAlert } from 'lucide-react';
import { KnockoutMatch } from '@/types/match';

export default function AdminKnockoutScoreScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { matches, loading: matchesLoading } = useKnockoutMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  const [savingId, setSavingId] = useState<string | null>(null);

  if (matchesLoading || teamsLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-[#8B5CF6] animate-spin" /></div>;

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

      // Calculate winner if final
      let winnerId = null;
      if (isFinal) {
        if (homeScore > awayScore) winnerId = match.homeTeamId;
        else if (awayScore > homeScore) winnerId = match.awayTeamId;
        else if (homePen > awayPen) winnerId = match.homeTeamId;
        else if (awayPen > homePen) winnerId = match.awayTeamId;
        else {
          alert("Knockout matches cannot end in a pure draw. Please enter penalty scores.");
          setSavingId(null);
          return;
        }
      }

      const matchRef = doc(db, 'leagues', leagueId, 'knockout', matchId);
      
      const payload: Partial<KnockoutMatch> = {
        homeScore,
        awayScore,
        homePenaltyScore: homePen > 0 || awayPen > 0 ? homePen : undefined,
        awayPenaltyScore: homePen > 0 || awayPen > 0 ? awayPen : undefined,
        status: isFinal ? 'played' : 'scheduled',
      };

      if (isFinal && winnerId) {
        payload.winnerTeamId = winnerId;
      }

      await updateDoc(matchRef, payload);
      
      // Note: In your architecture, the Flutter TournamentController handles the advancement logic 
      // (moving winner to nextMatchId) usually via a Cloud Function or client-side listener.
      alert("Score updated successfully!");
    } catch (error) {
      console.error("Failed to update score", error);
      alert("Failed to update score. Check permissions.");
    } finally {
      setSavingId(null);
    }
  };

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-[#8B5CF6] flex items-center gap-2">
            <GitMerge className="w-6 h-6" />
            Knockout Score Editor
          </h1>
          <p className="text-gray-400 mt-1">Manage bracket progression and penalty shootouts.</p>
        </div>
      </div>

      <div className="space-y-4">
        {matches.length === 0 ? (
          <Glass className="p-10 text-center text-gray-400 flex flex-col items-center">
             <ShieldAlert className="w-12 h-12 mb-3 opacity-50" />
             <p>No knockout matches found. Generate the bracket first.</p>
          </Glass>
        ) : (
          matches.map((match) => (
             // Only show matches where teams are actually assigned
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
  match, 
  homeTeamName, 
  awayTeamName, 
  isSaving, 
  onSave 
}: { 
  match: KnockoutMatch, 
  homeTeamName: string, 
  awayTeamName: string, 
  isSaving: boolean, 
  onSave: (id: string, h: number, a: number, hp: number, ap: number, isFinal: boolean) => void 
}) {
  const [hScore, setHScore] = useState(match.homeScore || 0);
  const [aScore, setAScore] = useState(match.awayScore || 0);
  const [hPen, setHPen] = useState(match.homePenaltyScore || 0);
  const [aPen, setAPen] = useState(match.awayPenaltyScore || 0);

  const isPlayed = match.status === 'played' || match.status === 'completed';

  return (
    <Glass className={`p-4 flex flex-col gap-4 border-l-4 ${isPlayed ? 'border-l-gray-600 opacity-70' : 'border-l-[#8B5CF6]'}`}>
      <div className="flex justify-between items-center text-xs font-bold text-gray-400 uppercase tracking-wider">
        <span>{match.roundName}</span>
        {isPlayed && <span className="text-brand-lime">Finished</span>}
      </div>

      <div className="flex flex-col md:flex-row items-center justify-between gap-4">
        {/* Teams and Main Score */}
        <div className="flex items-center justify-center gap-4 w-full md:w-auto flex-1">
          <div className="text-right flex-1 font-bold text-white truncate max-w-[120px]">{homeTeamName}</div>
          
          <input 
            type="number" min="0" value={hScore} 
            onChange={(e) => setHScore(parseInt(e.target.value) || 0)}
            className="w-14 bg-brand-surface border border-white/10 rounded-lg p-2 text-center text-lg font-black text-white focus:outline-none"
          />
          <span className="text-gray-500 font-bold">VS</span>
          <input 
            type="number" min="0" value={aScore} 
            onChange={(e) => setAScore(parseInt(e.target.value) || 0)}
            className="w-14 bg-brand-surface border border-white/10 rounded-lg p-2 text-center text-lg font-black text-white focus:outline-none"
          />

          <div className="text-left flex-1 font-bold text-white truncate max-w-[120px]">{awayTeamName}</div>
        </div>

        {/* Penalties (Only show if scores are tied, or if they already have penalties) */}
        {(hScore === aScore || hPen > 0 || aPen > 0) && (
          <div className="flex items-center justify-center gap-2 bg-white/5 p-2 rounded-lg border border-white/10">
            <span className="text-[10px] uppercase font-bold text-gray-400 mr-2">Pens</span>
            <input 
              type="number" min="0" value={hPen} 
              onChange={(e) => setHPen(parseInt(e.target.value) || 0)}
              className="w-10 bg-brand-surface border border-white/10 rounded text-center text-sm font-bold text-[#38BDF8]"
            />
            <span className="text-gray-500 text-xs">-</span>
            <input 
              type="number" min="0" value={aPen} 
              onChange={(e) => setAPen(parseInt(e.target.value) || 0)}
              className="w-10 bg-brand-surface border border-white/10 rounded text-center text-sm font-bold text-[#38BDF8]"
            />
          </div>
        )}

        {/* Actions */}
        <div className="flex items-center gap-2 w-full md:w-auto">
          {!isPlayed && (
            <button 
              onClick={() => onSave(match.id, hScore, aScore, hPen, aPen, true)}
              disabled={isSaving}
              className="w-full md:w-auto px-4 py-2 bg-[#8B5CF6] text-white hover:bg-[#7C3AED] rounded-lg text-sm font-bold flex items-center justify-center gap-2 transition-colors"
            >
              {isSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              Finalize Bracket
            </button>
          )}
        </div>
      </div>
    </Glass>
  );
}
