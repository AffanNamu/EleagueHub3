'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import {
  LeagueData,
  Membership,
  leagueIsInsideMasterLeague,
  isOwnerForViewer,
} from '@/lib/models/league';
import { FootballCategory, ALL_FOOTBALL_CATEGORIES } from '@/lib/models/footballCategory';
import {
  fetchMembershipsForUser,
  countParticipants,
  fetchLatestAnnouncement,
  LatestAnnouncement,
  detectPremiumUser,
  countCreatedLeagues,
  leaveLeagueWeb,
  joinLeagueByCode,
} from '@/lib/leagues/leaguesRepository';
import { LeagueCard, LeagueCardSkeleton } from '@/components/leagues/LeagueCard';
import { FootballCategoryChip } from '@/components/leagues/FootballCategoryChip';
import { JoinLeagueModal } from '@/components/leagues/JoinLeagueModal';
import { useLeagues } from '@/hooks/useLeagues';
import { Search, Plus, Trophy, Network, X, CreditCard, ShoppingBag, QrCode, Key } from 'lucide-react';

const FREE_LEAGUE_LIST_LIMIT = 3;

type ViewTab = 'leagues' | 'master';

export default function LeaguesListPage() {
  const router = useRouter();

  const [uid, setUid] = useState<string | null>(null);
  const { leagues, loading: leaguesLoading } = useLeagues();
  
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [participantCounts, setParticipantCounts] = useState<Record<string, number>>({});
  const [announcements, setAnnouncements] = useState<Record<string, LatestAnnouncement | null>>({});
  
  const [isPremium, setIsPremium] = useState(false);
  const [createdCount, setCreatedCount] = useState(0);
  const [checkingAccess, setCheckingAccess] = useState(true);
  const [dataLoading, setDataLoading] = useState(true);

  const [tab, setTab] = useState<ViewTab>('leagues');
  const [search, setSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<FootballCategory | null>(null);
  
  const [removingId, setRemovingId] = useState<string | null>(null);
  const [joinModalOpen, setJoinModalOpen] = useState(false);
  const [leaveTarget, setLeaveTarget] = useState<LeagueData | null>(null);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged((user) => {
      if (!user) {
        router.push('/login');
        return;
      }
      setUid(user.uid);
    });
    return () => unsubscribe();
  }, [router]);

  // STRICT PARITY: Fetch secondary data when real-time leagues update
  useEffect(() => {
    if (!uid || leaguesLoading) return;
    
    let isMounted = true;
    
    const loadSecondaryData = async () => {
      setDataLoading(true);
      try {
        const [premium, created, fetchedMemberships] = await Promise.all([
          detectPremiumUser(uid),
          countCreatedLeagues(uid),
          fetchMembershipsForUser(uid, leagues),
        ]);

        const counts: Record<string, number> = {};
        const anns: Record<string, LatestAnnouncement | null> = {};
        
        await Promise.all(
          leagues.map(async (l) => {
            const [count, ann] = await Promise.all([
              countParticipants(l.id),
              fetchLatestAnnouncement(l.id)
            ]);
            counts[l.id] = count;
            anns[l.id] = ann;
          }),
        );

        if (!isMounted) return;
        
        setMemberships(fetchedMemberships);
        setParticipantCounts(counts);
        setAnnouncements(anns);
        setIsPremium(premium);
        setCreatedCount(created);
      } catch (e) {
        console.error('[LeaguesListPage] secondary data load failed:', e);
      } finally {
        if (isMounted) {
          setCheckingAccess(false);
          setDataLoading(false);
        }
      }
    };

    loadSecondaryData();
    return () => { isMounted = false; };
  }, [uid, leagues, leaguesLoading]);

  const normalLeagues = useMemo(() => leagues.filter((l) => !leagueIsInsideMasterLeague(l)), [leagues]);
  const masterLeagues = useMemo(() => leagues.filter((l) => leagueIsInsideMasterLeague(l)), [leagues]);

  const filtered = useMemo(() => {
    let base = tab === 'leagues' ? normalLeagues : masterLeagues;
    if (categoryFilter) base = base.filter((l) => l.footballCategory === categoryFilter);

    const q = search.trim().toLowerCase();
    if (!q) return base;

    return base.filter((league) => {
      const ann = announcements[league.id];
      const haystack = [
        league.name,
        league.region,
        league.season,
        league.description,
        league.code,
        league.masterLeagueId,
        ann?.title ?? '',
        ann?.message ?? '',
      ]
        .join(' ')
        .toLowerCase();
      return haystack.includes(q);
    });
  }, [tab, normalLeagues, masterLeagues, categoryFilter, search, announcements]);

  const freeLimitReached = !isPremium && createdCount >= FREE_LEAGUE_LIST_LIMIT;
  const isLoadingTotal = leaguesLoading || dataLoading;

  const handleLeave = async () => {
    if (!leaveTarget || !uid) return;
    setRemovingId(leaveTarget.id);
    try {
      await leaveLeagueWeb(leaveTarget.id, uid);
      setLeaveTarget(null);
    } catch (e) {
      console.error('[LeaguesListPage] leave failed:', e);
    } finally {
      setRemovingId(null);
    }
  };

  const handleJoin = async (code: string, mode: 'participant' | 'viewer') => {
    if (!uid) return;
    const leagueId = await joinLeagueByCode(code, uid, mode);
    setJoinModalOpen(false);
    router.push(`/leagues/${leagueId}`);
  };

  const handleCreate = () => {
    if (checkingAccess) return;
    if (freeLimitReached) {
      router.push('/premium');
      return;
    }
    router.push('/leagues/create');
  };

  if (!uid) return null;

  return (
    <div className="min-h-screen bg-[#070B14] transition-colors duration-300 pb-20 md:pb-8">
      <div className="max-w-7xl mx-auto">
        
        {/* Header Section */}
        <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 mb-6 flex flex-col md:flex-row md:items-center justify-between gap-6 shadow-lg shadow-black/20">
          <div className="flex items-center gap-4">
            <div className="w-14 h-14 rounded-2xl bg-[#BEF264]/10 flex items-center justify-center shrink-0">
              <Trophy className="w-7 h-7 text-[#BEF264]" />
            </div>
            <div>
              <h1 className="text-2xl font-black text-white tracking-tight">My Leagues</h1>
              <p className="text-sm font-semibold text-gray-400 mt-1">
                {isLoadingTotal ? 'Loading...' : `${leagues.length} league${leagues.length === 1 ? '' : 's'}`}
              </p>
            </div>
          </div>

          <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
            <button
              onClick={() => setJoinModalOpen(true)}
              className="px-5 h-12 rounded-xl border border-[#1E293B] bg-[#1E293B]/30 text-white text-sm font-bold hover:bg-[#1E293B] transition-colors flex items-center justify-center gap-2"
            >
              <Key className="w-4 h-4" />
              Join ID
            </button>
            <button
              onClick={handleCreate}
              className={`px-5 h-12 rounded-xl text-sm font-black transition-all flex items-center justify-center gap-2 shadow-lg ${
                freeLimitReached 
                  ? 'bg-amber-500 text-white hover:brightness-110 shadow-amber-500/20' 
                  : 'bg-[#BEF264] text-[#0F172A] hover:brightness-110 shadow-[#BEF264]/20'
              }`}
            >
              {freeLimitReached ? <CreditCard className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
              {freeLimitReached ? 'Upgrade Plan' : 'Create'}
            </button>
          </div>
        </div>

        {/* Access Status Banner (Parity with Flutter) */}
        {!checkingAccess && (
          <div
            className={`mb-6 rounded-2xl border px-5 py-4 text-sm font-bold flex items-center gap-3 ${
              freeLimitReached
                ? 'bg-amber-500/10 border-amber-500/30 text-amber-400'
                : isPremium
                  ? 'bg-[#BEF264]/10 border-[#BEF264]/30 text-[#BEF264]'
                  : 'bg-[#1E293B]/50 border-[#1E293B] text-gray-400'
            }`}
          >
            {isPremium
              ? 'Paid plan active: you can create more than 3 leagues/competitions.'
              : freeLimitReached
                ? `Basic limit reached: you already created ${createdCount} / ${FREE_LEAGUE_LIST_LIMIT} leagues or competitions. Upgrade to create more.`
                : `Basic access active: you have used ${createdCount} / ${FREE_LEAGUE_LIST_LIMIT} shared creation slots.`}
          </div>
        )}

        {/* Search & Tabs */}
        <div className="flex flex-col lg:flex-row gap-4 mb-6">
          <div className="relative flex-1">
            <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search leagues, codes, announcements..."
              className="w-full pl-12 pr-10 py-3.5 bg-[#0B1221] border border-[#1E293B] rounded-2xl text-sm font-medium text-white placeholder:text-gray-500 focus:outline-none focus:border-[#BEF264] transition-colors shadow-inner"
            />
            {search && (
              <button onClick={() => setSearch('')} className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-500 hover:text-white">
                <X className="w-4 h-4" />
              </button>
            )}
          </div>

          <div className="inline-flex p-1.5 bg-[#0B1221] border border-[#1E293B] rounded-2xl lg:shrink-0 overflow-x-auto custom-scrollbar">
            <TabPill active={tab === 'leagues'} label="Leagues" count={normalLeagues.length} onClick={() => setTab('leagues')} icon={Trophy} />
            <TabPill active={tab === 'master'} label="Master" count={masterLeagues.length} onClick={() => setTab('master')} icon={Network} />
          </div>
        </div>

        {/* Categories */}
        <div className="flex gap-2 overflow-x-auto pb-4 mb-2 -mx-1 px-1 custom-scrollbar">
          <FootballCategoryChip category={null} selected={categoryFilter === null} onClick={() => setCategoryFilter(null)} />
          {ALL_FOOTBALL_CATEGORIES.map((cat) => (
            <FootballCategoryChip key={cat} category={cat} selected={categoryFilter === cat} onClick={() => setCategoryFilter(cat)} />
          ))}
        </div>

        {/* Content Grid */}
        {isLoadingTotal ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
            {Array.from({ length: 8 }).map((_, i) => <LeagueCardSkeleton key={i} />)}
          </div>
        ) : filtered.length === 0 ? (
          <EmptyState
            hasSearch={search.trim().length > 0}
            isMasterTab={tab === 'master'}
            freeLimitReached={freeLimitReached}
            onClearSearch={() => setSearch('')}
            onCreate={handleCreate}
          />
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
            {filtered.map((league) => {
              const owner = isOwnerForViewer(league, uid);
              const participant = memberships.some(
                (m) => m.leagueId === league.id && m.userId === uid && (m.role === 'organizer' || m.role === 'member'),
              );
              return (
                <LeagueCard
                  key={league.id}
                  league={league}
                  registered={participantCounts[league.id] ?? 0}
                  isOwner={owner}
                  isViewerOnly={!owner && !participant}
                  latestAnnouncement={announcements[league.id] ?? null}
                  showMasterBadge={tab !== 'master'}
                  removing={removingId === league.id}
                  onOpen={() => router.push(`/leagues/${league.id}`)}
                  onLeave={() => setLeaveTarget(league)}
                  onOpenWorkspace={
                    league.masterLeagueId.trim()
                      ? () => router.push(`/master-leagues/${league.masterLeagueId.trim()}`)
                      : undefined
                  }
                />
              );
            })}
          </div>
        )}
      </div>

      {joinModalOpen && <JoinLeagueModal onClose={() => setJoinModalOpen(false)} onJoin={handleJoin} />}
      {leaveTarget && <LeaveConfirmModal leagueName={leaveTarget.name} busy={removingId === leaveTarget.id} onCancel={() => setLeaveTarget(null)} onConfirm={handleLeave} />}
    </div>
  );
}

function TabPill({ active, label, count, onClick, icon: Icon }: { active: boolean; label: string; count: number; onClick: () => void; icon?: React.ComponentType<{ className?: string }>; }) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-2 px-5 py-2.5 rounded-xl text-xs font-black transition-all shrink-0 ${
        active ? 'bg-[#BEF264] text-[#0F172A]' : 'text-gray-400 hover:text-white hover:bg-white/5'
      }`}
    >
      {Icon && <Icon className="w-4 h-4" />}
      {label}
      {count > 0 && <span className={active ? "opacity-70" : "text-gray-500"}>({count})</span>}
    </button>
  );
}

function EmptyState({ hasSearch, isMasterTab, freeLimitReached, onClearSearch, onCreate }: { hasSearch: boolean; isMasterTab: boolean; freeLimitReached: boolean; onClearSearch: () => void; onCreate: () => void; }) {
  return (
    <div className="flex items-center justify-center py-24">
      <div className="text-center max-w-sm bg-[#0B1221] border border-[#1E293B] p-8 rounded-3xl shadow-xl shadow-black/20">
        <div className="w-16 h-16 mx-auto rounded-full bg-[#BEF264]/10 flex items-center justify-center mb-6">
          {hasSearch ? <Search className="w-8 h-8 text-[#BEF264]" /> : isMasterTab ? <Network className="w-8 h-8 text-[#BEF264]" /> : <Trophy className="w-8 h-8 text-[#BEF264]" />}
        </div>
        <h3 className="text-xl font-black text-white mb-2">
          {hasSearch ? 'No matches found' : isMasterTab ? 'No master competitions' : 'No leagues yet'}
        </h3>
        <p className="text-sm text-gray-400 font-medium leading-relaxed mb-8">
          {hasSearch
            ? 'Try another search term for league name, code, region, or announcement.'
            : isMasterTab
              ? 'Competitions you join from a master league container will appear here.'
              : 'Create your first league or join one with a code to get started.'}
        </p>
        <button
          onClick={hasSearch ? onClearSearch : onCreate}
          className={`w-full py-3.5 text-sm font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2 ${
            hasSearch ? 'bg-[#BEF264] text-[#0F172A]' : freeLimitReached ? 'bg-amber-500 text-white' : 'bg-[#BEF264] text-[#0F172A]'
          }`}
        >
          {hasSearch ? 'Clear Search' : freeLimitReached ? <CreditCard className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
          {hasSearch ? '' : freeLimitReached ? 'Upgrade Plan' : 'Create a league'}
        </button>
      </div>
    </div>
  );
}

function LeaveConfirmModal({ leagueName, busy, onCancel, onConfirm }: { leagueName: string; busy: boolean; onCancel: () => void; onConfirm: () => void; }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div className="w-full max-w-sm bg-[#0B1221] rounded-3xl shadow-2xl p-6 text-center border border-[#1E293B]">
        <div className="w-14 h-14 mx-auto rounded-full bg-red-500/10 flex items-center justify-center mb-4">
          <X className="w-6 h-6 text-red-500" />
        </div>
        <h3 className="text-lg font-black text-white mb-2">Remove League?</h3>
        <p className="text-sm text-gray-400 font-medium leading-relaxed mb-8">
          You will leave "{leagueName}" and it will no longer appear on your leagues screen.
        </p>
        <div className="flex gap-3">
          <button onClick={onCancel} disabled={busy} className="flex-1 py-3 rounded-xl border border-[#1E293B] text-white text-sm font-bold hover:bg-[#1E293B] transition-colors disabled:opacity-50">Cancel</button>
          <button onClick={onConfirm} disabled={busy} className="flex-1 py-3 rounded-xl bg-red-500 text-white text-sm font-black hover:bg-red-600 transition-colors disabled:opacity-50">
            {busy ? 'Removing...' : 'Remove'}
          </button>
        </div>
      </div>
    </div>
  );
}
