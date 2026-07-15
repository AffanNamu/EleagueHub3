'use client';

import { useParams, useRouter } from 'next/navigation';
import { useMatches } from '@/hooks/useMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, CalendarDays, Shield } from 'lucide-react';

export default function MatchesScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { matches, loading: matchesLoading } = useMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  if (matchesLoading || teamsLoading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 text-brand-lime animate-spin" />
      </div>
    );
  }

  const getTeam = (teamId: string) => teams.find(t => t.id === teamId);

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <button 
          onClick={() => router.back()}
          className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white">Fixtures & Results</h1>
          <p className="text-gray-400 mt-1">Live match tracking</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {matches.length === 0 ? (
          <Glass className="col-span-full p-10 text-center text-gray-400">
            No matches generated yet.
          </Glass>
        ) : (
          matches.map((match) => {
            const homeTeam = getTeam(match.homeTeamId);
            const awayTeam = getTeam(match.awayTeamId);

            return (
              <Glass key={match.id} className="p-4 flex flex-col gap-4">
                <div className="flex justify-between items-center text-xs text-gray-400 border-b border-white/5 pb-2">
                  <span className="flex items-center gap-1"><CalendarDays className="w-3 h-3"/> Round {match.roundNumber}</span>
                  <span className={`px-2 py-0.5 rounded text-white ${(match.status as string) === 'LIVE' ? 'bg-brand-red animate-pulse' : match.isPlayed ? 'bg-gray-700' : 'bg-brand-lime/20 text-brand-lime'}`}>
                    {match.status}
                  </span>
                </div>

                <div className="flex justify-between items-center px-4">
                  {/* Home Team */}
                  <div className="flex flex-col items-center gap-2 flex-1">
                    {homeTeam?.logoUrl ? (
                      <img src={homeTeam.logoUrl} alt={homeTeam.name} className="w-10 h-10 rounded-full" />
                    ) : <Shield className="w-10 h-10 text-gray-500" />}
                    <span className="text-sm font-bold text-center">{homeTeam?.name || 'TBD'}</span>
                  </div>

                  {/* Score */}
                  <div className="px-6 flex items-center justify-center text-2xl font-black tabular-nums tracking-widest text-brand-lime">
                    {match.isPlayed || (match.status as string) === 'LIVE' ? `${match.homeScore ?? 0} - ${match.awayScore ?? 0}` : 'VS'}
                  </div>

                  {/* Away Team */}
                  <div className="flex flex-col items-center gap-2 flex-1">
                    {awayTeam?.logoUrl ? (
                      <img src={awayTeam.logoUrl} alt={awayTeam.name} className="w-10 h-10 rounded-full" />
                    ) : <Shield className="w-10 h-10 text-gray-500" />}
                    <span className="text-sm font-bold text-center">{awayTeam?.name || 'TBD'}</span>
                  </div>
                </div>
              </Glass>
            );
          })
        )}
      </div>
    </div>
  );
}
