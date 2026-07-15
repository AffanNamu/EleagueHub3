import React from 'react';
import { Team, LeagueFormat } from '@/types/league';
import { FixtureMatch } from '@/types/match';
import { StandingsEngine } from '@/lib/algorithms/standingsEngine';
import { Shield } from 'lucide-react';

interface StandingsTableProps {
  teams: Team[];
  format?: LeagueFormat;
  matches?: FixtureMatch[];
}

export const StandingsTable: React.FC<StandingsTableProps> = ({ teams, format = 'classic', matches = [] }) => {
  // Use the exact ported Standings Engine for 1:1 mobile parity (H2H included)
  const sortedTeams = StandingsEngine.compute(teams, matches);

  const isGrouped = format === 'uclGroup' || format === 'worldCup';

  // Group teams by their groupId
  const groupedTeams = sortedTeams.reduce((acc, team) => {
    const gid = team.groupId || 'Unassigned';
    if (!acc[gid]) acc[gid] = [];
    acc[gid].push(team);
    return acc;
  }, {} as Record<string, Team[]>);

  // Sort group keys alphabetically (Group A, Group B, etc.)
  const groupKeys = Object.keys(groupedTeams).sort();

  const renderTable = (tableTeams: Team[], title?: string) => (
    <div key={title || 'classic'} className="mb-8 last:mb-0">
      {title && (
        <div className="bg-brand-surface border border-white/5 px-4 py-2 rounded-t-xl">
          <h3 className="font-black text-brand-lime tracking-widest uppercase text-sm">{title}</h3>
        </div>
      )}
      <div className="overflow-x-auto w-full">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="text-[10px] uppercase tracking-wider text-gray-500 border-b border-white/5">
              <th className="p-3 font-medium w-8 text-center">#</th>
              <th className="p-3 font-medium min-w-[120px]">Club</th>
              <th className="p-3 font-medium text-center">MP</th>
              <th className="p-3 font-medium text-center">W</th>
              <th className="p-3 font-medium text-center">D</th>
              <th className="p-3 font-medium text-center">L</th>
              <th className="p-3 font-medium text-center">GF</th>
              <th className="p-3 font-medium text-center">GA</th>
              <th className="p-3 font-medium text-center">GD</th>
              <th className="p-3 font-black text-brand-lime text-center">Pts</th>
            </tr>
          </thead>
          <tbody className="text-sm">
            {tableTeams.map((team, index) => (
              <tr key={team.id} className="border-b border-white/5 hover:bg-white/5 transition-colors group">
                <td className="p-3 text-center text-gray-500 font-bold">{index + 1}</td>
                <td className="p-3">
                  <div className="flex items-center gap-3">
                    {team.teamImageUrl || team.logoUrl ? (
                      <img src={team.teamImageUrl || team.logoUrl} alt={team.name} className="w-6 h-6 rounded-full object-cover shrink-0" />
                    ) : (
                      <div className="w-6 h-6 rounded-full bg-brand-surfaceDark flex items-center justify-center shrink-0">
                        <Shield className="w-3 h-3 text-gray-400" />
                      </div>
                    )}
                    <span className="font-bold text-white group-hover:text-brand-lime transition-colors">{team.name}</span>
                  </div>
                </td>
                <td className="p-3 text-center text-gray-400 tabular-nums">{team.played || 0}</td>
                <td className="p-3 text-center text-gray-400 tabular-nums">{team.won || 0}</td>
                <td className="p-3 text-center text-gray-400 tabular-nums">{team.drawn || 0}</td>
                <td className="p-3 text-center text-gray-400 tabular-nums">{team.lost || 0}</td>
                <td className="p-3 text-center text-gray-400 tabular-nums">{team.goalsFor || 0}</td>
                <td className="p-3 text-center text-gray-400 tabular-nums">{team.goalsAgainst || 0}</td>
                <td className="p-3 text-center font-medium tabular-nums text-white">{(team.goalDifference || 0) > 0 ? `+${team.goalDifference}` : team.goalDifference || 0}</td>
                <td className="p-3 text-center font-black text-brand-lime tabular-nums">{team.finalPoints || 0}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );

  if (!isGrouped) {
    return renderTable(sortedTeams);
  }

  return (
    <div className="flex flex-col gap-4">
      {groupKeys.map(key => renderTable(groupedTeams[key], key))}
    </div>
  );
};
