'use client';

import { useParams, useRouter } from 'next/navigation';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Glass } from '@/components/ui/Glass';
import { Loader2, ArrowLeft, LayoutGrid, Shield } from 'lucide-react';
import { Team } from '@/types/league';

export default function GroupDrawScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league } = useLeagueDetail(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  if (teamsLoading) return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 animate-spin text-brand-lime"/></div>;

  const groupedTeams = teams.reduce((acc, team) => {
    const gid = team.groupId || 'Unassigned';
    if (!acc[gid]) acc[gid] = [];
    acc[gid].push(team);
    return acc;
  }, {} as Record<string, Team[]>);

  const groupKeys = Object.keys(groupedTeams).sort();

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-10">
      <div className="flex items-center gap-4">
        <button onClick={() => router.back()} className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-[#38BDF8] flex items-center gap-2">
            <LayoutGrid className="w-6 h-6" />
            Group Draw Overview
          </h1>
          <p className="text-gray-400 mt-1">Visualization of the current group stages.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        {groupKeys.map(group => (
          <Glass key={group} className="p-0 overflow-hidden flex flex-col h-full border border-white/10">
            <div className="bg-[#38BDF8]/20 px-4 py-3 border-b border-[#38BDF8]/30">
              <h3 className="font-black text-[#38BDF8] uppercase tracking-widest text-sm">{group}</h3>
            </div>
            <div className="p-4 flex flex-col gap-3 flex-1">
              {groupedTeams[group].map((team) => (
                <div key={team.id} className="flex items-center gap-3">
                  {team.teamImageUrl || team.logoUrl ? (
                    <img src={team.teamImageUrl || team.logoUrl} className="w-6 h-6 rounded-full object-cover shrink-0" alt=""/>
                  ) : (
                    <div className="w-6 h-6 rounded-full bg-brand-surfaceDark flex items-center justify-center shrink-0">
                      <Shield className="w-3 h-3 text-gray-400" />
                    </div>
                  )}
                  <span className="font-bold text-white text-sm truncate">{team.name}</span>
                </div>
              ))}
            </div>
            <div className="px-4 py-2 bg-black/40 text-[10px] font-bold text-gray-500 uppercase tracking-widest text-right">
              {groupedTeams[group].length} Teams
            </div>
          </Glass>
        ))}
      </div>
    </div>
  );
}
