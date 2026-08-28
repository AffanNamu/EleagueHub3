'use client';

import { useState, useMemo, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useMatches } from '@/hooks/useMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { Loader2, ArrowLeft, Edit, ShieldCheck, CheckCircle2, ChevronLeft, ChevronRight } from 'lucide-react';
import { updateMatchScoreWeb } from '@/lib/leagues/leagueAdminRepository';

export default function AdminScoreMgmtScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const { matches, loading: matchesLoading } = useMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  const [selectedRound, setSelectedRound] = useState<number>(1);
  const [selectedGroup, setSelectedGroup] = useState<string | null>(null);
  const [savingMatches, setSavingMatches] = useState<Set<string>>(new Set());

  const isGroupedFormat = league?.format === 'uclGroup' || league?.format === 1 || league?.format === 'worldCup' || league?.format === 3;

  const totalRounds = useMemo(() => {
    if (!matches.length) return 0;
    let filtered = matches;
    if (isGroupedFormat && selectedGroup) {
      filtered = filtered.filter(m => m.groupId === selectedGroup);
    }
    if (!filtered.length) return 0;
    return Math.max(...filtered.map(m => m.roundNumber || 1));
  }, [matches, isGroupedFormat, selectedGroup]);

  const groups = useMemo(() => {
    if (!isGroupedFormat) return [];
    const gSet = new Set<string>();
    matches.forEach(m => {
      if (m.groupId && m.groupId.trim()) gSet.add(m.groupId.trim());
    });
    return Array.from(gSet).sort();
  }, [matches, isGroupedFormat]);

  const displayMatches = useMemo(() => {
    let filtered = matches;
    if (isGroupedFormat && selectedGroup) {
      filtered = filtered.filter(m => m.groupId === selectedGroup);
    }
    return filtered
      .filter(m => (m.roundNumber || 1) === selectedRound)
      .sort((a, b) => (a.sortIndex || 0) - (b.sortIndex || 0));
  }, [matches, isGroupedFormat, selectedGroup, selectedRound]);

  useEffect(() => {
    if (totalRounds > 0 && selectedRound > totalRounds) {
      setSelectedRound(totalRounds);
    }
  }, [totalRounds, selectedRound]);

  const handleUpdateScore = async (matchId: string, homeScore: number, awayScore: number) => {
    if (savingMatches.has(matchId)) return;
    setSavingMatches(prev => new Set(prev).add(matchId));
    try {
      await updateMatchScoreWeb(leagueId, matchId, homeScore, awayScore);
    } catch (e) {
      console.error(e);
      alert('Failed to update score. Check console.');
    } finally {
      setSavingMatches(prev => {
        const next = new Set(prev);
        next.delete(matchId);
        return next;
      });
    }
  };

  if (leagueLoading || matchesLoading || teamsLoading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  const getTeam = (teamId: string) => teams.find(t => t.id === teamId);

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-16">
      
      <div className="flex items-center gap-4 px-2">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-3">
            <Edit className="w-6 h-6 text-[#BEF264]" />
            Score Editor
          </h1>
          <p className="text-sm font-semibold text-gray-400 mt-1">Admin Score Management</p>
        </div>
      </div>

      <div className="space-y-4 sticky top-16 z-30 bg-[#070B14]/90 backdrop-blur-md py-4 px-2 border-b border-[#1E293B] -mx-4 sm:mx-0 sm:px-0">
        {isGroupedFormat && groups.length > 0 && (
          <div className="flex gap-2 overflow-x-auto pb-2 custom-scrollbar">
            <button
              onClick={() => { setSelectedGroup(null); setSelectedRound(1); }}
              className={`px-5 py-2.5 rounded-full text-xs font-black transition-all shrink-0 border ${
                selectedGroup === null ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]' : 'bg-[#0B1221] text-gray-400 border-[#1E293B] hover:border-gray-500 hover:text-white'
              }`}
            >
              All Groups
            </button>
            {groups.map(g => (
              <button
                key={g}
                onClick={() => { setSelectedGroup(g); setSelectedRound(1); }}
                className={`px-5 py-2.5 rounded-full text-xs font-black transition-all shrink-0 border ${
                  selectedGroup === g ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]' : 'bg-[#0B1221] text-gray-400 border-[#1E293B] hover:border-gray-500 hover:text-white'
                }`}
              >
                {g.replace('Group ', 'Grp ')}
              </button>
            ))}
          </div>
        )}

        {totalRounds > 0 && (
          <div className="flex gap-2 overflow-x-auto pb-2 custom-scrollbar">
            {Array.from({ length: totalRounds }).map((_, i) => {
              const r = i + 1;
              return (
                <button
                  key={r}
                  onClick={() => setSelectedRound(r)}
                  className={`px-5 py-2.5 rounded-xl text-xs font-black transition-all shrink-0 border ${
                    selectedRound === r ? 'bg-[#BEF264] text-[#0F172A] border-[#BEF264]' : 'bg-[#0B1221] text-gray-400 border-[#1E293B] hover:border-gray-500 hover:text-white'
                  }`}
                >
                  Round {r}
                </button>
              );
            })}
          </div>
        )}
      </div>

      <div className="px-2 space-y-4">
        {displayMatches.length === 0 ? (
          <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-10 text-center">
            <h3 className="text-white font-black text-lg">No Matches Found</h3>
            <p className="text-gray-400 text-sm mt-2 font-medium">There are no fixtures to edit for this selection.</p>
          </div>
        ) : (
          displayMatches.map((match) => {
            const home = getTeam(match.homeTeamId);
            const away = getTeam(match.awayTeamId);
            const isSaving = savingMatches.has(match.id!);
            return (
              <ScoreEntryTile
                key={match.id}
                match={match}
                homeTeam={home}
                awayTeam={away}
                isGroupedFormat={isGroupedFormat}
                isSaving={isSaving}
                onSave={handleUpdateScore}
              />
            );
          })
        )}
      </div>
    </div>
  );
}

function ScoreEntryTile({ match, homeTeam, awayTeam, isGroupedFormat, isSaving, onSave }: any) {
  const [homeScore, setHomeScore] = useState(match.homeScore ?? 0);
  const [awayScore, setAwayScore] = useState(match.awayScore ?? 0);

  useEffect(() => {
    setHomeScore(match.homeScore ?? 0);
    setAwayScore(match.awayScore ?? 0);
  }, [match.homeScore, match.awayScore]);

  const isCompleted = match.status === 'completed' || match.status === 'played' || match.isPlayed;

  return (
    <div className={`bg-[#0B1221] border border-[#1E293B] rounded-3xl p-5 shadow-xl transition-all ${isSaving ? 'opacity-50 pointer-events-none' : ''}`}>
      {isGroupedFormat && match.groupId && (
        <div className="mb-4">
          <span className="text-[10px] font-black uppercase tracking-widest text-gray-500 bg-[#1E293B] px-2 py-1 rounded">
            {match.groupId}
          </span>
        </div>
      )}

      <div className="flex items-center justify-between gap-4">
        <div className="flex-1 flex items-center justify-end gap-3">
          <span className="text-sm font-black text-white text-right line-clamp-1">{homeTeam?.name || 'TBD'}</span>
          <div className="w-8 h-8 rounded-full bg-[#1E293B] border border-white/10 flex items-center justify-center shrink-0 overflow-hidden">
            {homeTeam?.teamImageUrl ? <img src={homeTeam.teamImageUrl} className="w-full h-full object-cover" /> : <ShieldCheck className="w-4 h-4 text-gray-500" />}
          </div>
        </div>

        <div className="shrink-0 flex flex-col items-center gap-1">
          <span className="text-xs font-black text-gray-500">VS</span>
          <span className={`px-2 py-0.5 rounded text-[9px] font-black uppercase tracking-widest ${isCompleted ? 'bg-[#BEF264]/10 text-[#BEF264]' : 'bg-[#1E293B] text-gray-400'}`}>
            {isCompleted ? 'Completed' : 'Pending'}
          </span>
        </div>

        <div className="flex-1 flex items-center justify-start gap-3">
          <div className="w-8 h-8 rounded-full bg-[#1E293B] border border-white/10 flex items-center justify-center shrink-0 overflow-hidden">
            {awayTeam?.teamImageUrl ? <img src={awayTeam.teamImageUrl} className="w-full h-full object-cover" /> : <ShieldCheck className="w-4 h-4 text-gray-500" />}
          </div>
          <span className="text-sm font-black text-white text-left line-clamp-1">{awayTeam?.name || 'TBD'}</span>
        </div>
      </div>

      <div className="mt-6 pt-6 border-t border-[#1E293B] flex items-center justify-center gap-6">
        {/* Home Stepper */}
        <div className="flex items-center bg-[#1E293B]/50 border border-[#1E293B] rounded-xl p-1">
          <button onClick={() => setHomeScore(Math.max(0, homeScore - 1))} className="w-8 h-8 rounded-lg bg-[#0B1221] flex items-center justify-center text-gray-400 hover:text-white transition-colors">
            <ChevronLeft className="w-4 h-4" />
          </button>
          <span className="w-12 text-center text-xl font-black text-white tabular-nums">{homeScore}</span>
          <button onClick={() => setHomeScore(homeScore + 1)} className="w-8 h-8 rounded-lg bg-[#BEF264]/10 text-[#BEF264] hover:bg-[#BEF264]/20 flex items-center justify-center transition-colors">
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>

        <span className="text-xl font-black text-gray-600">:</span>

        {/* Away Stepper */}
        <div className="flex items-center bg-[#1E293B]/50 border border-[#1E293B] rounded-xl p-1">
          <button onClick={() => setAwayScore(Math.max(0, awayScore - 1))} className="w-8 h-8 rounded-lg bg-[#0B1221] flex items-center justify-center text-gray-400 hover:text-white transition-colors">
            <ChevronLeft className="w-4 h-4" />
          </button>
          <span className="w-12 text-center text-xl font-black text-white tabular-nums">{awayScore}</span>
          <button onClick={() => setAwayScore(awayScore + 1)} className="w-8 h-8 rounded-lg bg-[#BEF264]/10 text-[#BEF264] hover:bg-[#BEF264]/20 flex items-center justify-center transition-colors">
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>

        <button 
          onClick={() => onSave(match.id, homeScore, awayScore)} 
          disabled={isSaving}
          className="w-12 h-12 rounded-xl bg-[#BEF264] text-[#0F172A] flex items-center justify-center hover:brightness-110 transition-all shadow-lg shadow-[#BEF264]/20 ml-2 shrink-0"
        >
          {isSaving ? <Loader2 className="w-5 h-5 animate-spin" /> : <CheckCircle2 className="w-6 h-6" />}
        </button>
      </div>
    </div>
  );
}
