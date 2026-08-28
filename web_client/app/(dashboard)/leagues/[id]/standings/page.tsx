'use client';

import { useParams, useRouter } from 'next/navigation';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { useMatches } from '@/hooks/useMatches';
import { Glass } from '@/components/ui/Glass';
import { StandingsTable } from '@/components/leagues/StandingsTable';
import { Loader2, ArrowLeft, Trophy } from 'lucide-react';

export default function LeagueStandingsScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);
  const { matches, loading: matchesLoading } = useMatches(leagueId);

  if (leagueLoading || teamsLoading || matchesLoading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  if (!league) {
    return (
      <div className="text-center py-20 text-red-500 font-black text-xl">League not found.</div>
    );
  }

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-16 px-4 sm:px-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-3">
            <Trophy className="w-6 h-6 text-[#BEF264]" />
            Live Standings
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">{league.name}</p>
        </div>
      </div>

      <Glass className="p-0 overflow-hidden shadow-2xl border border-[#1E293B]">
        <div className="p-4 sm:p-6 bg-[#070B14]">
          {teams.length === 0 ? (
             <div className="text-center py-16">
               <Trophy className="w-12 h-12 text-[#1E293B] mx-auto mb-4" />
               <p className="text-gray-500 font-bold">No teams registered yet.</p>
             </div>
          ) : (
            <StandingsTable 
              teams={teams} 
              format={league.format} 
              worldCupFormat={league.settings?.worldCupFormat}
              matches={matches} 
            />
          )}
        </div>
      </Glass>
    </div>
  );
}
