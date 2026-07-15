import React from 'react';
import { KnockoutMatch } from '@/types/match';
import { Team } from '@/types/league';
import { Shield } from 'lucide-react';
import { cn } from '@/lib/utils';

interface KnockoutCardProps {
  match: KnockoutMatch;
  getTeam: (id: string) => Team | undefined;
}

export const KnockoutCard: React.FC<KnockoutCardProps> = ({ match, getTeam }) => {
  const homeTeam = getTeam(match.homeTeamId as string);
  const awayTeam = getTeam(match.awayTeamId as string);

  const TeamRow = ({ team, score, isWinner }: { team?: Team, score?: number, isWinner: boolean }) => (
    <div className={cn(
      "flex items-center justify-between p-2 rounded-lg transition-colors",
      isWinner ? "bg-brand-surface border border-white/5" : ""
    )}>
      <div className="flex items-center gap-2 overflow-hidden">
        {team?.logoUrl ? (
          <img src={team.logoUrl} alt={team.name} className="w-5 h-5 rounded-full" />
        ) : (
          <Shield className="w-5 h-5 text-gray-500" />
        )}
        <span className={cn(
          "text-sm truncate",
          isWinner ? "font-bold text-white" : "text-gray-400 font-medium"
        )}>
          {team?.name || 'TBD'}
        </span>
      </div>
      <span className={cn(
        "font-black tabular-nums pl-2",
        isWinner ? "text-brand-lime" : "text-gray-500"
      )}>
        {score ?? '-'}
      </span>
    </div>
  );

  const homeWins = (match as any).isPlayed && (match.homeScore! > match.awayScore! || (match.homeScore === match.awayScore && match.homePenaltyScore! > match.awayPenaltyScore!));
  const awayWins = (match as any).isPlayed && !homeWins && match.homeScore !== match.awayScore;

  return (
    <div className="w-64 bg-brand-surfaceDark border border-white/10 rounded-xl overflow-hidden shadow-xl flex flex-col">
      <div className="bg-black/40 px-3 py-1.5 flex justify-between items-center text-[10px] font-bold text-gray-400 uppercase tracking-wider border-b border-white/5">
        <span>{match.roundName}</span>
        {(match.status as string) === 'LIVE' && <span className="text-brand-red animate-pulse flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-brand-red"></span> LIVE</span>}
      </div>
      <div className="p-1 space-y-1">
        <TeamRow team={homeTeam} score={match.homeScore} isWinner={homeWins} />
        <TeamRow team={awayTeam} score={match.awayScore} isWinner={awayWins} />
      </div>
      {(match.homePenaltyScore !== undefined && match.homePenaltyScore > 0) && (
        <div className="text-[10px] text-center bg-white/5 text-gray-400 py-1">
          Pens: {match.homePenaltyScore} - {match.awayPenaltyScore}
        </div>
      )}
    </div>
  );
};
