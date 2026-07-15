'use client';

import { useParams, useRouter } from 'next/navigation';
import { useKnockoutMatches } from '@/hooks/useKnockoutMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { KnockoutCard } from '@/components/leagues/KnockoutCard';
import { ArrowLeft, Loader2, GitMerge } from 'lucide-react';

export default function KnockoutScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { matches, loading: matchesLoading } = useKnockoutMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  if (matchesLoading || teamsLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  const getTeam = (teamId: string) => teams.find(t => t.id === teamId);

  // Group matches by round for rendering columns
  const rounds = Array.from(new Set(matches.map(m => m.roundName)));

  return (
    <div className="space-y-6">

      {/* SVG Bracket Lines CSS Setup */}
      <style dangerouslySetInnerHTML={{__html: `
        .bracket-col { position: relative; }
        .bracket-col:not(:last-child)::after {
          content: '';
          position: absolute;
          top: 0; right: -24px; bottom: 0; width: 24px;
        }
        .bracket-match { position: relative; }
        .bracket-match::after {
          content: '';
          position: absolute;
          right: -24px;
          top: 50%;
          width: 24px;
          border-bottom: 2px solid rgba(255,255,255,0.1);
        }
        .bracket-col:not(:last-child) .bracket-match:nth-child(odd)::before {
          content: '';
          position: absolute;
          right: -24px;
          top: 50%;
          height: 100%; /* Spans to the next match */
          border-right: 2px solid rgba(255,255,255,0.1);
        }
      `}} />

      {/* Header */}
      <div className="flex items-center gap-4">
        <button 
          onClick={() => router.back()}
          className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            <GitMerge className="w-6 h-6 text-brand-lime" />
            Tournament Bracket
          </h1>
          <p className="text-gray-400 mt-1">Knockout phase live tracking</p>
        </div>
      </div>

      {matches.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <GitMerge className="w-16 h-16 text-gray-500 mb-4" />
          <h3 className="text-xl font-semibold text-white">No Bracket Generated</h3>
          <p className="text-gray-400 mt-2">The knockout phase hasn't been drawn yet.</p>
        </Glass>
      ) : (
        <Glass className="p-4 md:p-8 overflow-x-auto">
          {/* Horizontal scroll container for the tree */}
          <div className="flex gap-12 min-w-max pb-8">
            {rounds.map(round => (
              <div key={round} className="bracket-col flex flex-col gap-8 justify-around min-h-[500px]">
                <h3 className="text-center font-black text-gray-500 tracking-widest uppercase mb-4">{round}</h3>
                
                <div className="flex flex-col gap-6 justify-around flex-1">
                  {matches.filter(m => m.roundName === round).map(match => (
                    <div key={match.id} className="bracket-match relative group">
                      <KnockoutCard match={match} getTeam={getTeam} />
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </Glass>
      )}
    </div>
  );
}
