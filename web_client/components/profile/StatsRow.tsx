'use client';

import { UserStats } from '@/lib/profile/teamProfileRepository';

/**
 * The full 11-stat set shown on mobile's public_team_profile_screen.dart
 * (_StatsSection) — Followers, Following, Competitions, Trophies, Matches,
 * Wins, Draws, Losses, Goals, Conceded, Win %. Previously the web only
 * rendered 4 of these (Followers/Matches/Win Rate/Trophies).
 */
export function StatsRow({ stats }: { stats: UserStats | null }) {
  const s = stats || {
    followersCount: 0, followingCount: 0, competitionsJoined: 0, trophies: 0,
    matchesPlayed: 0, wins: 0, draws: 0, losses: 0, goalsScored: 0,
    goalsConceded: 0, winPercentage: 0,
  };

  const cards: [string, string][] = [
    ['Followers', `${s.followersCount}`],
    ['Following', `${s.followingCount}`],
    ['Competitions', `${s.competitionsJoined}`],
    ['Trophies', `${s.trophies}`],
    ['Matches', `${s.matchesPlayed}`],
    ['Wins', `${s.wins}`],
    ['Draws', `${s.draws}`],
    ['Losses', `${s.losses}`],
    ['Goals', `${s.goalsScored}`],
    ['Conceded', `${s.goalsConceded}`],
    ['Win %', `${s.winPercentage.toFixed(0)}%`],
  ];

  return (
    <div className="flex gap-3 overflow-x-auto pb-1 custom-scrollbar -mx-1 px-1">
      {cards.map(([label, value]) => (
        <div
          key={label}
          className="shrink-0 min-w-[92px] p-4 rounded-2xl border bg-[#0B1221] border-[#1E293B] text-white shadow-lg flex flex-col justify-center"
        >
          <span className="text-lg font-black tabular-nums">{value}</span>
          <span className="text-[10px] font-bold uppercase tracking-widest mt-1 text-gray-500">{label}</span>
        </div>
      ))}
    </div>
  );
}
