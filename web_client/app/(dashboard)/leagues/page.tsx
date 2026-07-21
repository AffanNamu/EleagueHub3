
/*  LeaguesListPage */
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
  fetchLeaguesForUser,
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
import { Search, RefreshCw, Plus, Trophy, Network, X } from 'lucide-react';

const FREE_LEAGUE_LIST_LIMIT = 3;

type ViewTab = 'leagues' | 'master';

export default function LeaguesListPage() {
  const router = useRouter();

  const [uid, setUid] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [leagues, setLeagues] = useState<LeagueData[]>([]);
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [participantCounts, setParticipantCounts] = useState<Record<string, number>>({});
  const [announcements, setAnnouncements] = useState<Record<string, LatestAnnouncement | null>>({});
  const [isPremium, setIsPremium] = useState(false);
  const [createdCount, setCreatedCount] = useState(0);
  const [checkingAccess, setCheckingAccess] = useState(true);

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

  const loadAll = useCallback(async () => {
    if (!uid) return;
    setLoading(true);
    setCheckingAccess(true);

    try {
      const [fetchedLeagues, premium, created] = await Promise.all([
        fetchLeaguesForUser(uid),
        detectPremiumUser(uid),
        countCreatedLeagues(uid),
      ]);

      const fetchedMemberships = await fetchMembershipsForUser(uid, fetchedLeagues);

      const counts: Record<string, number> = {};
      await Promise.all(
        fetchedLeagues.map(async (l) => {
          counts[l.id] = await countParticipants(l.id);
        }),
      );

      setLeagues(fetchedLeagues);
      setMemberships(fetchedMemberships);
      setParticipantCounts(counts);
      setIsPremium(premium);
      setCreatedCount(created);
      setCheckingAccess(false);
      setLoading(false);

      fetchedLeagues.forEach(async (l) => {
        const ann = await fetchLatestAnnouncement(l.id);
        setAnnouncements((prev) => ({ ...prev, [l.id]: ann }));
      });
    } catch (e) {
      console.error('[LeaguesListPage] load failed:', e);
      setLoading(false);
      setCheckingAccess(false);
    }
  }, [uid]);

  useEffect(() => {
    if (uid) loadAll();
  }, [uid, loadAll]);

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

  const handleLeave = async () => {
    if (!leaveTarget || !uid) return;
    setRemovingId(leaveTarget.id);
    try {
      await leaveLeagueWeb(leaveTarget.id, uid);
      setLeaveTarget(null);
      await loadAll();
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
    await loadAll();
    router.push(`/leagues/${leagueId}`);
  };

  if (!uid) return null;

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-[#081120] transition-colors duration-300">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 rounded-2xl bg-brand-lime/15 border border-brand-lime/30 flex items-center justify-center shrink-0">
              <Trophy className="w-5 h-5 text-brand-lime" />
            </div>
            <div>
              <h1 className="text-xl font-black text-slate-900 dark:text-white tracking-tight">My Leagues</h1>
              <p className="text-xs font-semibold text-slate-400">
                {loading ? 'Loading...' : `${leagues.length} league${leagues.length === 1 ? '' : 's'}`}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={loadAll}
              className="w-10 h-10 rounded-xl border border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-500 dark:text-slate-400 hover:text-slate-800 dark:hover:text-white hover:bg-slate-50 dark:hover:bg-white/10 flex items-center justify-center transition-colors"
              aria-label="Refresh"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
            <button
              onClick={() => setJoinModalOpen(true)}
              className="px-4 h-10 rounded-xl border border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-700 dark:text-slate-200 text-sm font-bold hover:bg-slate-50 dark:hover:bg-white/10 transition-colors"
            >
              Join league
            </button>
            <button
              onClick={() => router.push('/leagues/create')}
              className="px-4 h-10 rounded-xl bg-brand-lime text-slate-900 text-sm font-black hover:brightness-95 transition-all flex items-center gap-1.5 shadow-lg shadow-brand-lime/20"
            >
              <Plus className="w-4 h-4" />
              Create
            </button>
          </div>
        </div>

        {!checkingAccess && (
          <div
            className={`mb-6 rounded-2xl border px-4 py-3 text-xs font-bold flex items-center gap-2 ${
              freeLimitReached
                ? 'bg-amber-50 dark:bg-amber-500/10 border-amber-200 dark:border-amber-500/20 text-amber-700 dark:text-amber-400'
                : isPremium
                  ? 'bg-brand-lime/10 border-brand-lime/30 text-brand-lime'
                  : 'bg-slate-100 dark:bg-white/5 border-slate-200 dark:border-white/10 text-slate-500 dark:text-slate-400'
            }`}
          >
            {isPremium
              ? 'Paid plan active — you can create more than 3 leagues/competitions.'
              : freeLimitReached
                ? `Basic limit reached: ${createdCount} / ${FREE_LEAGUE_LIST_LIMIT} leagues or competitions created. Upgrade to create more.`
                : `Basic access: ${createdCount} / ${FREE_LEAGUE_LIST_LIMIT} shared creation slots used.`}
          </div>
        )}

        <div className="relative mb-4">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search leagues, codes, announcements..."
            className="w-full pl-11 pr-10 py-3 bg-white dark:bg-[#0F172A] border border-slate-200 dark:border-white/10 rounded-2xl text-sm font-medium text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:border-brand-lime transition-colors"
          />
          {search && (
            <button
              onClick={() => setSearch('')}
              className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 dark:hover:text-white"
            >
              <X className="w-4 h-4" />
            </button>
          )}
        </div>

        <div className="inline-flex p-1 bg-white dark:bg-[#0F172A] border border-slate-200 dark:border-white/10 rounded-full mb-4">
          <TabPill
            active={tab === 'leagues'}
            label="Leagues"
            count={normalLeagues.length}
            onClick={() => setTab('leagues')}
          />
          <TabPill
            active={tab === 'master'}
            label="Master"
            count={masterLeagues.length}
            onClick={() => setTab('master')}
            icon={Network}
          />
        </div>

        <div className="flex gap-2 overflow-x-auto pb-2 mb-6 -mx-1 px-1">
          <FootballCategoryChip category={null} selected={categoryFilter === null} onClick={() => setCategoryFilter(null)} />
          {ALL_FOOTBALL_CATEGORIES.map((cat) => (
            <FootballCategoryChip
              key={cat}
              category={cat}
              selected={categoryFilter === cat}
              onClick={() => setCategoryFilter(cat)}
            />
          ))}
        </div>

        {loading ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-5">
            {Array.from({ length: 6 }).map((_, i) => (
              <LeagueCardSkeleton key={i} />
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <EmptyState
            hasSearch={search.trim().length > 0}
            isMasterTab={tab === 'master'}
            onClearSearch={() => setSearch('')}
            onCreate={() => router.push('/leagues/create')}
          />
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-5">
            {filtered.map((league) => {
              const viewerUid = uid;
              const owner = isOwnerForViewer(league, viewerUid);
              const participant = memberships.some(
                (m) => m.leagueId === league.id && m.userId === viewerUid && (m.role === 'organizer' || m.role === 'member'),
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

      {leaveTarget && (
        <LeaveConfirmModal
          leagueName={leaveTarget.name}
          busy={removingId === leaveTarget.id}
          onCancel={() => setLeaveTarget(null)}
          onConfirm={handleLeave}
        />
      )}
    </div>
  );
}

function TabPill({
  active,
  label,
  count,
  onClick,
  icon: Icon,
}: {
  active: boolean;
  label: string;
  count: number;
  onClick: () => void;
  icon?: React.ComponentType<{ className?: string }>;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1.5 px-4 py-2 rounded-full text-xs font-black transition-all ${
        active 
          ? 'bg-brand-lime text-slate-900' 
          : 'text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-white'
      }`}
    >
      {Icon && <Icon className="w-3.5 h-3.5" />}
      {label}
      {count > 0 && <span className="opacity-70">({count})</span>}
    </button>
  );
}

function EmptyState({
  hasSearch,
  isMasterTab,
  onClearSearch,
  onCreate,
}: {
  hasSearch: boolean;
  isMasterTab: boolean;
  onClearSearch: () => void;
  onCreate: () => void;
}) {
  return (
    <div className="flex items-center justify-center py-20">
      <div className="text-center max-w-sm">
        <div className="w-16 h-16 mx-auto rounded-2xl bg-brand-lime/10 border border-brand-lime/30 flex items-center justify-center mb-5">
          {hasSearch ? (
            <Search className="w-7 h-7 text-brand-lime" />
          ) : isMasterTab ? (
            <Network className="w-7 h-7 text-brand-lime" />
          ) : (
            <Trophy className="w-7 h-7 text-brand-lime" />
          )}
        </div>
        <h3 className="text-lg font-black text-slate-900 dark:text-white mb-2">
          {hasSearch ? 'No leagues match your search' : isMasterTab ? 'No master competitions yet' : 'No leagues yet'}
        </h3>
        <p className="text-sm text-slate-400 font-medium leading-relaxed mb-6">
          {hasSearch
            ? 'Try another search term for league name, code, region, or announcement.'
            : isMasterTab
              ? 'Competitions you join from a master league container will appear here.'
              : 'Create your first league or join one with a code to get started.'}
        </p>
        <button
          onClick={hasSearch ? onClearSearch : onCreate}
          className="px-5 py-3 bg-brand-lime text-slate-900 text-sm font-black rounded-2xl hover:brightness-95 transition-all inline-flex items-center gap-2"
        >
          {hasSearch ? 'Clear search' : (
            <>
              <Plus className="w-4 h-4" />
              Create a league
            </>
          )}
        </button>
      </div>
    </div>
  );
}

function LeaveConfirmModal({
  leagueName,
  busy,
  onCancel,
  onConfirm,
}: {
  leagueName: string;
  busy: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="w-full max-w-sm bg-white dark:bg-[#0F172A] rounded-3xl shadow-2xl p-6 text-center border border-white/10">
        <h3 className="text-base font-black text-slate-900 dark:text-white mb-2">Remove league from your list?</h3>
        <p className="text-sm text-slate-500 dark:text-slate-400 font-medium leading-relaxed mb-6">
          You will leave "{leagueName}" and it will no longer appear on your leagues screen.
        </p>
        <div className="flex gap-3">
          <button
            onClick={onCancel}
            disabled={busy}
            className="flex-1 py-3 rounded-xl border border-slate-200 dark:border-white/10 text-slate-700 dark:text-slate-300 text-sm font-bold hover:bg-slate-50 dark:hover:bg-white/5 transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            disabled={busy}
            className="flex-1 py-3 rounded-xl bg-brand-lime text-slate-900 text-sm font-black hover:brightness-95 transition-all disabled:opacity-50"
          >
            {busy ? 'Removing...' : 'Remove'}
          </button>
        </div>
      </div>
    </div>
  );
}
