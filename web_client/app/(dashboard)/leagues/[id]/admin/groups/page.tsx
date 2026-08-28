'use client';

import { useParams, useRouter } from 'next/navigation';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, LayoutGrid, Shield, Globe } from 'lucide-react';
import { Team } from '@/types/league';

export default function GroupDrawScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  if (teamsLoading || leagueLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-[#BEF264]"/></div>;

  const isWorldCup = league?.format === 'worldCup' || league?.format === 3;

  const groupedTeams = teams.reduce((acc, team) => {
    const gid = team.groupId || 'Unassigned';
    if (!acc[gid]) acc[gid] = [];
    acc[gid].push(team);
    return acc;
  }, {} as Record<string, Team[]>);

  const groupKeys = Object.keys(groupedTeams).sort();

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-16 px-4 sm:px-6">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className={`text-2xl md:text-3xl font-black flex items-center gap-3 ${isWorldCup ? 'text-amber-500' : 'text-[#38BDF8]'}`}>
            {isWorldCup ? <Globe className="w-6 h-6" /> : <LayoutGrid className="w-6 h-6" />}
            Group Draw Overview
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Visualization of the current group stages.</p>
        </div>
      </div>

      {groupKeys.length === 0 ? (
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-16 text-center">
          <LayoutGrid className="w-12 h-12 text-[#1E293B] mx-auto mb-4" />
          <p className="text-gray-500 font-bold">No groups assigned yet.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
          {groupKeys.map(group => (
            <Glass key={group} className="p-0 overflow-hidden flex flex-col h-full border border-[#1E293B] bg-[#0B1221]">
              <div className={`px-5 py-3 border-b ${isWorldCup ? 'bg-amber-500/10 border-amber-500/20' : 'bg-[#38BDF8]/10 border-[#38BDF8]/20'}`}>
                <h3 className={`font-black uppercase tracking-widest text-sm ${isWorldCup ? 'text-amber-500' : 'text-[#38BDF8]'}`}>
                  {group.replace('Group', 'Grp')}
                </h3>
              </div>
              <div className="p-5 flex flex-col gap-4 flex-1">
                {groupedTeams[group].map((team) => (
                  <div key={team.id} className="flex items-center gap-3">
                    {team.teamImageUrl || team.logoUrl ? (
                      <img src={team.teamImageUrl || team.logoUrl} className="w-7 h-7 rounded-full object-cover shrink-0 border border-white/5" alt=""/>
                    ) : (
                      <div className="w-7 h-7 rounded-full bg-[#1E293B] flex items-center justify-center shrink-0 border border-white/5">
                        <Shield className="w-3.5 h-3.5 text-gray-400" />
                      </div>
                    )}
                    <span className="font-bold text-white text-sm truncate">{team.name}</span>
                  </div>
                ))}
              </div>
              <div className="px-5 py-2.5 bg-[#070B14] border-t border-[#1E293B] text-[10px] font-black text-gray-500 uppercase tracking-widest text-right">
                {groupedTeams[group].length} Teams
              </div>
            </Glass>
          ))}
        </div>
      )}
    </div>
  );
}
