'use client';

import { useState, useMemo, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useMatches } from '@/hooks/useMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Loader2, ArrowLeft, Trophy, CalendarDays, ShieldCheck, ChevronRight } from 'lucide-react';
import { auth } from '@/lib/firebase';

export default function FixturesScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const { matches, loading: matchesLoading } = useMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  const [selectedRound, setSelectedRound] = useState<number>(1);
  const [selectedGroup, setSelectedGroup] = useState<string | null>(null);

  const isGroupedFormat = league?.format === 'uclGroup' || league?.format === 1 || league?.format === 'worldCup' || league?.format === 3;

  // Extract total rounds
  const totalRounds = useMemo(() => {
    if (!matches.length) return 0;
    let filtered = matches;
    if (isGroupedFormat && selectedGroup) {
      filtered = filtered.filter(m => m.groupId === selectedGroup);
    }
    if (!filtered.length) return 0;
    return Math.max(...filtered.map(m => m.roundNumber || 1));
  }, [matches, isGroupedFormat, selectedGroup]);

  // Extract unique groups
  const groups = useMemo(() => {
    if (!isGroupedFormat) return [];
    const gSet = new Set<string>();
    matches.forEach(m => {
      if (m.groupId && m.groupId.trim()) gSet.add(m.groupId.trim());
    });
    return Array.from(gSet).sort();
  }, [matches, isGroupedFormat]);

  // Filter matches for display
  const displayMatches = useMemo(() => {
    let filtered = matches;
    if (isGroupedFormat && selectedGroup) {
      filtered = filtered.filter(m => m.groupId === selectedGroup);
    }
    return filtered
      .filter(m => (m.roundNumber || 1) === selectedRound)
      .sort((a, b) => (a.sortIndex || 0) - (b.sortIndex || 0));
  }, [matches, isGroupedFormat, selectedGroup, selectedRound]);

  // Adjust round if out of bounds after changing group
  useEffect(() => {
    if (totalRounds > 0 && selectedRound > totalRounds) {
      setSelectedRound(totalRounds);
    }
  }, [totalRounds, selectedRound]);

  if (leagueLoading || matchesLoading || teamsLoading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  const getTeam = (teamId: string) => teams.find(t => t.id === teamId);

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-16">
      
      {/* ── HEADER ── */}
      <div className="flex items-center gap-4 px-2">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-3">
            <CalendarDays className="w-6 h-6 text-[#BEF264]" />
            Fixtures
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">{league?.name}</p>
        </div>
      </div>

      {/* ── SELECTORS ── */}
      <div className="space-y-4 sticky top-16 z-30 bg-[#070B14]/90 backdrop-blur-md py-4 px-2 border-b border-[#1E293B] -mx-4 sm:mx-0 sm:px-0">
        
        {/* Group Selector (Only for Group / World Cup) */}
        {isGroupedFormat && groups.length > 0 && (
          <div className="flex gap-2 overflow-x-auto pb-2 custom-scrollbar">
            <button
              onClick={() => { setSelectedGroup(null); setSelectedRound(1); }}
              className={`px-5 py-2.5 rounded-full text-xs font-black transition-all shrink-0 border ${
                selectedGroup === null 
                  ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]' 
                  : 'bg-[#0B1221] text-gray-400 border-[#1E293B] hover:border-gray-500 hover:text-white'
              }`}
            >
              All Groups
            </button>
            {groups.map(g => (
              <button
                key={g}
                onClick={() => { setSelectedGroup(g); setSelectedRound(1); }}
                className={`px-5 py-2.5 rounded-full text-xs font-black transition-all shrink-0 border ${
                  selectedGroup === g 
                    ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]' 
                    : 'bg-[#0B1221] text-gray-400 border-[#1E293B] hover:border-gray-500 hover:text-white'
                }`}
              >
                {g.replace('Group ', 'Grp ')}
              </button>
            ))}
          </div>
        )}

        {/* Round Selector */}
        {totalRounds > 0 && (
          <div className="flex gap-2 overflow-x-auto pb-2 custom-scrollbar">
            {Array.from({ length: totalRounds }).map((_, i) => {
              const r = i + 1;
              return (
                <button
                  key={r}
                  onClick={() => setSelectedRound(r)}
                  className={`px-5 py-2.5 rounded-xl text-xs font-black transition-all shrink-0 border ${
                    selectedRound === r 
                      ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]' 
                      : 'bg-[#0B1221] text-gray-400 border-[#1E293B] hover:border-gray-500 hover:text-white'
                  }`}
                >
                  Round {r}
                </button>
              );
            })}
          </div>
        )}
      </div>

      {/* ── MATCH LIST ── */}
      <div className="px-2">
        {displayMatches.length === 0 ? (
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-10 text-center flex flex-col items-center">
            <Trophy className="w-12 h-12 text-gray-600 mb-4" />
            <h3 className="text-white font-black text-lg">No Matches Found</h3>
            <p className="text-gray-400 text-sm mt-2 font-medium">There are no fixtures generated for this round yet.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {displayMatches.map((match) => {
              const home = getTeam(match.homeTeamId);
              const away = getTeam(match.awayTeamId);
              const isFinished = match.status === 'completed' || match.status === 'played' || match.isPlayed;
              const hasScore = match.homeScore != null && match.awayScore != null;

              return (
                <div 
                  key={match.id}
                  onClick={() => router.push(`/leagues/${leagueId}/matches/${match.id}`)}
                  className="bg-[#0B1221] border border-[#1E293B] hover:border-white/10 hover:bg-[#1E293B]/30 transition-all rounded-3xl p-5 cursor-pointer shadow-lg group"
                >
                  {/* Group Label */}
                  {isGroupedFormat && match.groupId && (
                    <div className="mb-4">
                      <span className="text-[10px] font-black uppercase tracking-widest text-gray-500">
                        {match.groupId}
                      </span>
                    </div>
                  )}

                  <div className="flex items-center justify-between">
                    {/* Home Team */}
                    <div className="flex-1 flex flex-col items-end gap-2 pr-4">
                      <div className="w-10 h-10 rounded-full bg-[#1E293B] border border-white/10 flex items-center justify-center overflow-hidden shrink-0">
                        {home?.teamImageUrl ? <img src={home.teamImageUrl} className="w-full h-full object-cover" /> : <ShieldCheck className="w-5 h-5 text-gray-500" />}
                      </div>
                      <span className="text-sm font-bold text-white text-right line-clamp-2 leading-tight">
                        {home?.name || 'TBD'}
                      </span>
                    </div>

                    {/* Score / VS Box */}
                    <div className="shrink-0 w-20 flex flex-col items-center justify-center">
                      <div className={`px-4 py-2 rounded-xl border ${
                        isFinished && hasScore 
                          ? 'bg-[#BEF264]/10 border-[#BEF264]/30 text-[#BEF264]' 
                          : 'bg-[#1E293B] border-transparent text-gray-400'
                      }`}>
                        <span className="text-lg font-black tracking-wider">
                          {isFinished && hasScore ? `${match.homeScore} - ${match.awayScore}` : 'VS'}
                        </span>
                      </div>
                    </div>

                    {/* Away Team */}
                    <div className="flex-1 flex flex-col items-start gap-2 pl-4">
                      <div className="w-10 h-10 rounded-full bg-[#1E293B] border border-white/10 flex items-center justify-center overflow-hidden shrink-0">
                        {away?.teamImageUrl ? <img src={away.teamImageUrl} className="w-full h-full object-cover" /> : <ShieldCheck className="w-5 h-5 text-gray-500" />}
                      </div>
                      <span className="text-sm font-bold text-white text-left line-clamp-2 leading-tight">
                        {away?.name || 'TBD'}
                      </span>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
