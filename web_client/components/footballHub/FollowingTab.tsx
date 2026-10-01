'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { ChevronRight, Shield, User } from 'lucide-react';
import { getFollowedPlayers, getFollowedTeams, FollowedFootballEntity } from '@/lib/footballHub/footballFollowsRepository';
import { currentFootballSeasonGuess } from '@/lib/footballHub/footballHubRepository';

type SubTab = 'teams' | 'players';

export function FollowingTab() {
  const router = useRouter();
  const [subTab, setSubTab] = useState<SubTab>('teams');
  const [teams, setTeams] = useState<FollowedFootballEntity[] | null>(null);
  const [players, setPlayers] = useState<FollowedFootballEntity[] | null>(null);

  useEffect(() => {
    getFollowedTeams().then(setTeams);
    getFollowedPlayers().then(setPlayers);
  }, []);

  const items = subTab === 'teams' ? teams : players;
  const emptyLabel =
    subTab === 'teams'
      ? 'You are not following any teams yet.\nOpen a team from Matches or Leagues to follow it.'
      : 'You are not following any players yet.\nOpen a player from a team squad to follow them.';

  return (
    <div>
      <div className="flex gap-2 mb-4">
        <button
          onClick={() => setSubTab('teams')}
          className={`px-4 h-9 rounded-lg text-sm font-bold transition-colors ${
            subTab === 'teams' ? 'bg-[#BEF264] text-[#0F172A]' : 'bg-[#1E293B]/50 text-gray-300'
          }`}
        >
          Teams
        </button>
        <button
          onClick={() => setSubTab('players')}
          className={`px-4 h-9 rounded-lg text-sm font-bold transition-colors ${
            subTab === 'players' ? 'bg-[#BEF264] text-[#0F172A]' : 'bg-[#1E293B]/50 text-gray-300'
          }`}
        >
          Players
        </button>
      </div>

      {items === null && <p className="text-sm text-gray-400">Loading...</p>}
      {items?.length === 0 && <p className="text-sm text-gray-400 whitespace-pre-line">{emptyLabel}</p>}

      <div className="space-y-2">
        {items?.map((item) => (
          <button
            key={item.id}
            onClick={() => {
              if (subTab === 'teams') router.push(`/football/team/${item.id}`);
              else router.push(`/football/player/${item.id}?season=${currentFootballSeasonGuess()}`);
            }}
            className="w-full flex items-center gap-3 bg-[#0B1221] border border-[#1E293B] rounded-xl px-4 py-3 text-left hover:border-[#BEF264]/30 transition-colors"
          >
            {item.imageUrl ? (
              <img src={item.imageUrl} alt="" className="w-8 h-8 rounded-full object-cover" />
            ) : (
              <div className="w-8 h-8 rounded-full bg-[#1E293B] flex items-center justify-center">
                {subTab === 'teams' ? <Shield className="w-4 h-4 text-gray-400" /> : <User className="w-4 h-4 text-gray-400" />}
              </div>
            )}
            <p className="flex-1 text-sm font-bold text-white truncate">{item.name}</p>
            <ChevronRight className="w-4 h-4 text-gray-500 shrink-0" />
          </button>
        ))}
      </div>
    </div>
  );
}
