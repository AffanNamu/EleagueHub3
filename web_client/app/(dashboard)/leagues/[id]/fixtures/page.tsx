'use client';

import { useState, useMemo, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useMatches } from '@/hooks/useMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { useLeagueDetail } from '@/hooks/useLeagueDetail';
import { useGlobalChatAccess } from '@/hooks/useGlobalChat';
import { sendLeagueImageMessageWeb } from '@/hooks/useChat';
import { sendGlobalMessageWeb } from '@/lib/chat/chatRepository';
import { renderFixturesShareCardPng } from '@/lib/leagues/fixturesShareCard';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { Loader2, ArrowLeft, Trophy, CalendarDays, ShieldCheck, CheckSquare, Square, Share2, X, Users, Globe } from 'lucide-react';
import { auth } from '@/lib/firebase';

export default function FixturesScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { league, loading: leagueLoading } = useLeagueDetail(leagueId);
  const { matches, loading: matchesLoading } = useMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  const [authUid, setAuthUid] = useState<string | null>(null);
  useEffect(() => {
    const unsub = auth.onAuthStateChanged((u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);
  const { status: globalChatStatus } = useGlobalChatAccess(authUid);
  const canShareToGlobalChat = globalChatStatus === 'approved';

  const [selectedRound, setSelectedRound] = useState<number>(1);
  const [selectedGroup, setSelectedGroup] = useState<string | null>(null);

  // Fixture sharing (share selected fixtures as an image to League/Global
  // Chat) — mirrors fixtures_screen.dart's selection mode +
  // _shareSelectedFixturesToChat. Organizer-only, matching
  // _canAdminSelectFixtures = _isOrganizer.
  const [selectMode, setSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [sharing, setSharing] = useState(false);
  const [showTargetPicker, setShowTargetPicker] = useState(false);

  const isOwner = !!authUid && (league?.organizerUid === authUid || league?.organizerUserId === authUid);

  const isGroupedFormat = league?.format === 'uclGroup' || league?.format === 'worldCup';

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

  const getTeam = (teamId: string) => teams.find(t => t.id === teamId);

  const toggleSelected = (matchId: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(matchId)) next.delete(matchId);
      else next.add(matchId);
      return next;
    });
  };

  const exitSelectMode = () => {
    setSelectMode(false);
    setSelectedIds(new Set());
  };

  const handleCardClick = (matchId: string) => {
    if (selectMode) {
      toggleSelected(matchId);
      return;
    }
    router.push(`/leagues/${leagueId}/matches/${matchId}`);
  };

  const openSharePicker = () => {
    if (selectedIds.size === 0) return;
    if (!canShareToGlobalChat) {
      shareTo('league');
      return;
    }
    setShowTargetPicker(true);
  };

  const shareTo = async (target: 'league' | 'global') => {
    if (!auth.currentUser || selectedIds.size === 0) return;
    setShowTargetPicker(false);
    setSharing(true);
    try {
      const selectedMatches = matches.filter((m) => selectedIds.has(m.id));
      const teamNames: Record<string, string> = {};
      for (const t of teams) teamNames[t.id] = t.name;

      const blob = await renderFixturesShareCardPng({
        leagueName: league?.name || 'League',
        leagueLogoUrl: league?.leagueImageUrl,
        subtitle: isGroupedFormat && selectedGroup ? selectedGroup : undefined,
        matches: selectedMatches.map((m) => ({
          roundNumber: m.roundNumber || 1,
          groupId: m.groupId,
          sortIndex: m.sortIndex || 0,
          homeTeamId: m.homeTeamId,
          awayTeamId: m.awayTeamId,
          homeScore: m.homeScore,
          awayScore: m.awayScore,
        })),
        teamNames,
      });

      const file = new File([blob], `fixtures_share_${leagueId}_${Date.now()}.png`, { type: 'image/png' });
      const folder = target === 'global' ? 'eleaguehub/global_chat_images' : `eleaguehub/league_chat_images/${leagueId}`;
      const { secureUrl } = await uploadImageFile({ file, folder });

      if (target === 'global') {
        await sendGlobalMessageWeb({
          senderId: auth.currentUser.uid,
          senderName: auth.currentUser.displayName || 'Player',
          senderPhoto: auth.currentUser.photoURL || '',
          type: 'image',
          text: '',
          imageUrl: secureUrl,
        });
      } else {
        await sendLeagueImageMessageWeb(leagueId, secureUrl);
      }

      exitSelectMode();
    } catch (e) {
      console.error('[FixturesScreen] share failed:', e);
      alert('Could not share fixtures. Please try again.');
    } finally {
      setSharing(false);
    }
  };

  if (leagueLoading || matchesLoading || teamsLoading) {
    return (
      <div className="flex justify-center py-20">
        <Loader2 className="w-10 h-10 text-[#BEF264] animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-5xl mx-auto pb-16">

      {/* ── HEADER ── */}
      <div className="flex items-center gap-4 px-2">
        {selectMode ? (
          <>
            <button onClick={exitSelectMode} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
              <X className="w-5 h-5 text-white" />
            </button>
            <h1 className="text-xl font-black text-white flex-1">{selectedIds.size} selected</h1>
            <button
              onClick={openSharePicker}
              disabled={sharing || selectedIds.size === 0}
              className="p-2.5 bg-[#BEF264] text-[#0F172A] rounded-xl disabled:opacity-40 flex items-center gap-2 px-4 font-black text-xs"
            >
              {sharing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Share2 className="w-4 h-4" />}
              Share
            </button>
          </>
        ) : (
          <>
            <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors">
              <ArrowLeft className="w-5 h-5 text-white" />
            </button>
            <div className="flex-1">
              <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight flex items-center gap-3">
                <CalendarDays className="w-6 h-6 text-[#BEF264]" />
                Fixtures
              </h1>
              <p className="text-sm font-semibold text-gray-400 mt-1">{league?.name}</p>
            </div>
            {isOwner && (
              <button
                onClick={() => setSelectMode(true)}
                className="px-4 py-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-xl transition-colors text-xs font-black text-gray-300 flex items-center gap-2"
              >
                <CheckSquare className="w-4 h-4" /> Select
              </button>
            )}
          </>
        )}
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
              const isSelected = selectedIds.has(match.id);

              return (
                <div
                  key={match.id}
                  onClick={() => handleCardClick(match.id)}
                  className={`relative bg-[#0B1221] border transition-all rounded-3xl p-5 cursor-pointer shadow-lg group ${
                    isSelected ? 'border-[#BEF264]' : 'border-[#1E293B] hover:border-white/10 hover:bg-[#1E293B]/30'
                  }`}
                >
                  {selectMode && (
                    <div className="absolute top-4 right-4">
                      {isSelected ? <CheckSquare className="w-5 h-5 text-[#BEF264]" /> : <Square className="w-5 h-5 text-gray-500" />}
                    </div>
                  )}

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
                        {home?.teamImageUrl ? <img src={home.teamImageUrl} alt="" className="w-full h-full object-cover" /> : <ShieldCheck className="w-5 h-5 text-gray-500" />}
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
                        {away?.teamImageUrl ? <img src={away.teamImageUrl} alt="" className="w-full h-full object-cover" /> : <ShieldCheck className="w-5 h-5 text-gray-500" />}
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

      {showTargetPicker && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-4" onClick={() => setShowTargetPicker(false)}>
          <div className="w-full max-w-sm bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4" onClick={(e) => e.stopPropagation()}>
            <p className="text-white font-black text-center mb-3">Share to…</p>
            <button
              onClick={() => shareTo('league')}
              className="w-full flex items-center gap-3 p-3.5 rounded-xl hover:bg-white/5 transition-colors text-left"
            >
              <Users className="w-5 h-5 text-[#BEF264]" />
              <div>
                <p className="text-sm font-black text-white">League Chat</p>
                <p className="text-xs text-gray-400 font-semibold">Share inside this league</p>
              </div>
            </button>
            <button
              onClick={() => shareTo('global')}
              className="w-full flex items-center gap-3 p-3.5 rounded-xl hover:bg-white/5 transition-colors text-left"
            >
              <Globe className="w-5 h-5 text-[#BEF264]" />
              <div>
                <p className="text-sm font-black text-white">Global Chat</p>
                <p className="text-xs text-gray-400 font-semibold">Share to global public chat</p>
              </div>
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
