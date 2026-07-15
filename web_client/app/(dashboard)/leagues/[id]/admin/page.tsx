'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { doc, updateDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { useMatches } from '@/hooks/useMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, Save } from 'lucide-react';
import { FixtureMatch } from '@/types/match';

export default function AdminScoreScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { matches, loading: matchesLoading } = useMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  const [savingId, setSavingId] = useState<string | null>(null);

  if (matchesLoading || teamsLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;

  const getTeam = (teamId: string) => teams.find(t => t.id === teamId);

  const handleUpdateScore = async (matchId: string, homeScore: number, awayScore: number, isFinal: boolean) => {
    setSavingId(matchId);
    try {
      const matchRef = doc(db, 'leagues', leagueId, 'matches', matchId);
      await updateDoc(matchRef, {
        homeScore,
        awayScore,
        isPlayed: isFinal,
        status: isFinal ? 'FINISHED' : 'LIVE',
      });
      // In your Flutter codebase, Supabase/Firebase Cloud Functions automatically calculate the Standings
      // when a match is marked as 'isPlayed = true'.
    } catch (error) {
      console.error("Failed to update score", error);
      alert("Failed to update score. Check permissions.");
    } finally {
      setSavingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-brand-red">Admin: Score Management</h1>
          <p className="text-gray-400 mt-1">Live updates instantly sync to mobile devices</p>
        </div>
      </div>

      <div className="space-y-4">
        {matches.filter(m => !m.isPlayed || (m.status as string) === 'LIVE').map((match) => (
          <ScoreEditorRow 
            key={match.id} 
            match={match} 
            homeTeamName={getTeam(match.homeTeamId)?.name || 'TBD'}
            awayTeamName={getTeam(match.awayTeamId)?.name || 'TBD'}
            isSaving={savingId === match.id}
            onSave={(h, a, isFinal) => handleUpdateScore(match.id, h, a, isFinal)}
          />
        ))}
        {matches.filter(m => !m.isPlayed).length === 0 && (
          <Glass className="p-8 text-center text-gray-400">All matches have been completed.</Glass>
        )}
      </div>
    </div>
  );
}

function ScoreEditorRow({ match, homeTeamName, awayTeamName, isSaving, onSave }: { match: FixtureMatch, homeTeamName: string, awayTeamName: string, isSaving: boolean, onSave: (h: number, a: number, isFinal: boolean) => void }) {
  const [hScore, setHScore] = useState(match.homeScore || 0);
  const [aScore, setAScore] = useState(match.awayScore || 0);

  return (
    <Glass className="p-4 flex flex-col md:flex-row items-center justify-between gap-4 border-l-4 border-l-brand-red">
      <div className="flex items-center gap-4 w-full md:w-auto">
        <div className="text-right flex-1 md:w-32 font-bold text-white">{homeTeamName}</div>
        
        <input 
          type="number" min="0" value={hScore} 
          onChange={(e) => setHScore(parseInt(e.target.value) || 0)}
          className="w-16 bg-brand-surface border border-white/10 rounded-lg p-2 text-center text-xl font-black text-brand-lime focus:outline-none"
        />
        <span className="text-gray-500 font-bold">VS</span>
        <input 
          type="number" min="0" value={aScore} 
          onChange={(e) => setAScore(parseInt(e.target.value) || 0)}
          className="w-16 bg-brand-surface border border-white/10 rounded-lg p-2 text-center text-xl font-black text-brand-lime focus:outline-none"
        />

        <div className="text-left flex-1 md:w-32 font-bold text-white">{awayTeamName}</div>
      </div>

      <div className="flex items-center gap-2 w-full md:w-auto">
        <button 
          onClick={() => onSave(hScore, aScore, false)}
          disabled={isSaving}
          className="flex-1 md:flex-none px-4 py-2 bg-brand-red/20 text-brand-red hover:bg-brand-red/30 rounded-lg text-sm font-bold transition-colors"
        >
          Update Live
        </button>
        <button 
          onClick={() => onSave(hScore, aScore, true)}
          disabled={isSaving}
          className="flex-1 md:flex-none px-4 py-2 bg-brand-lime text-brand-navy hover:bg-brand-lime/90 rounded-lg text-sm font-bold flex items-center justify-center gap-2 transition-colors"
        >
          {isSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
          Finish Match
        </button>
      </div>
    </Glass>
  );
}
