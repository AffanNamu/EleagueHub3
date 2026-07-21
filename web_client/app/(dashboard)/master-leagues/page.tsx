'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useMasterLeagues } from '@/hooks/useMasterLeagues';
import { useEntitlements, canCreateWorkspace } from '@/hooks/useEntitlements';
import { PanelCard } from '@/components/masterLeagues/PanelCard';
import { StatCard } from '@/components/masterLeagues/StatCard';
import { cloudinaryOptimizedUrl } from '@/lib/cloudinary/cloudinaryUpload';
import {
  Loader2,
  Network,
  Users,
  PlusCircle,
  Compass,
  Trophy,
  Layers,
  Sparkles,
  ChevronRight,
  BadgeCheck
} from 'lucide-react';
import Link from 'next/link';
import { MASTER_LEAGUE_PLANS } from '@/types/masterLeague';

const PLAN_TINT: Record<string, string> = {
  basic: '#38BDF8',
  pro: '#B8E928',
  elite: '#F59E0B',
};

export default function MasterLeaguesScreen() {
  const router = useRouter();
  const { created, joined, loading, error } = useMasterLeagues(true);
  const { activePlan, ownedCount, loading: entLoading } = useEntitlements();
  const [checking, setChecking] = useState(false);

  const planDef = MASTER_LEAGUE_PLANS[activePlan];
  const canCreate = !entLoading && canCreateWorkspace(activePlan, ownedCount);
  const planTint = PLAN_TINT[activePlan];

  const handleCreateClick = () => {
    setChecking(true);
    router.push('/master-leagues/create');
  };

  const renderCard = (workspace: (typeof created)[number]) => {
    const tint = PLAN_TINT[workspace.plan] ?? '#38BDF8';
    return (
      <Link href={`/master-leagues/${workspace.id}`} key={workspace.id}>
        <div className="bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-2xl overflow-hidden group transition-all relative shadow-lg">
          <div className="h-28 bg-[#070B14] relative overflow-hidden">
            {workspace.organizerProfile.bannerUrl ? (
              <img
                src={cloudinaryOptimizedUrl(workspace.organizerProfile.bannerUrl, { width: 900, height: 300, crop: 'fill' })}
                alt=""
                className="w-full h-full object-cover opacity-70 group-hover:opacity-90 transition-opacity"
              />
            ) : (
              <div
                className="w-full h-full"
                style={{
                  background: `radial-gradient(circle at 30% 30%, ${tint}1A, transparent 60%), #070B14`,
                }}
              />
            )}
            <div className="absolute inset-0 bg-gradient-to-t from-[#0B1221] to-transparent" />
            {workspace.plan === 'elite' && (
              <div className="absolute top-2.5 left-2.5 flex items-center gap-1 px-2 py-1 bg-[#070B14]/80 backdrop-blur-md border border-[#F59E0B]/30 rounded-lg text-[9px] font-black text-[#F59E0B] uppercase tracking-wider">
                <Sparkles className="w-2.5 h-2.5" /> Elite
              </div>
            )}
          </div>

          <div className="px-4 pb-4 relative">
            <div className="w-14 h-14 rounded-xl overflow-hidden border-4 border-[#0B1221] bg-[#070B14] -mt-7 shrink-0 relative">
              {workspace.organizerProfile.logoUrl ? (
                <img
                  src={cloudinaryOptimizedUrl(workspace.organizerProfile.logoUrl, { width: 150, height: 150, crop: 'fill' })}
                  className="w-full h-full object-cover"
                  alt=""
                />
              ) : (
                <div className="w-full h-full flex items-center justify-center">
                  <Network className="w-5 h-5 text-gray-600" />
                </div>
              )}
              {workspace.verifiedBadge && (
                <div className="absolute -bottom-1 -right-1 w-5 h-5 bg-[#070B14] rounded-full flex items-center justify-center border-2 border-[#0B1221]">
                   <BadgeCheck className="w-3.5 h-3.5 text-[#FEF08A] fill-[#F59E0B] drop-shadow-[0_0_5px_rgba(245,158,11,0.9)]" />
                </div>
              )}
            </div>

            <div className="mt-2">
              <h3 className="font-bold text-white text-base flex items-center gap-1.5 truncate group-hover:text-brand-lime transition-colors">
                {workspace.name}
              </h3>
              <p className="text-xs text-gray-500 mt-1 line-clamp-2 leading-relaxed">
                {workspace.organizerProfile.bio || 'Official tournament organizer.'}
              </p>
            </div>

            <div className="mt-3.5 pt-3.5 border-t border-[#1E293B] flex items-center justify-between text-xs">
              <div className="flex items-center gap-1.5 text-gray-500 font-bold">
                <Users className="w-3.5 h-3.5 text-brand-lime" />
                {workspace.followersCount}
              </div>
              <div className="flex items-center gap-1.5 text-gray-500 font-bold">
                <Trophy className="w-3.5 h-3.5" style={{ color: tint }} />
                {workspace.analytics.totalTournamentsCreated}
              </div>
              <ChevronRight className="w-4 h-4 text-gray-600 group-hover:text-brand-lime transition-colors" />
            </div>
          </div>
        </div>
      </Link>
    );
  };

  return (
    <div className="max-w-7xl mx-auto pb-16 space-y-8">
      <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
        <div className="absolute -top-40 left-1/4 w-[500px] h-[500px] rounded-full bg-brand-lime/[0.05] blur-[120px]" />
        <div className="absolute top-60 right-1/3 w-[400px] h-[400px] rounded-full bg-[#38BDF8]/[0.05] blur-[120px]" />
      </div>

      {/* ── Header ─────────────────────────────────────────────────────── */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-11 h-11 rounded-xl bg-brand-lime/10 border border-brand-lime/25 flex items-center justify-center">
            <Network className="w-5 h-5 text-brand-lime" />
          </div>
          <div>
            <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight">Organizer Workspaces</h1>
            <p className="text-gray-500 text-sm mt-0.5">
              {entLoading ? 'Checking your plan...' : 'Manage your organizer hubs and communities.'}
            </p>
          </div>
        </div>

        <div className="flex gap-3">
          <Link
            href="/master-leagues/discovery"
            className="flex items-center justify-center gap-2 px-4 py-2.5 bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] text-white font-bold text-sm rounded-xl transition-colors"
          >
            <Compass className="w-4 h-4" />
            Discover
          </Link>
          <button
            onClick={handleCreateClick}
            disabled={checking}
            className="flex items-center justify-center gap-2 px-4 py-2.5 bg-brand-lime text-brand-navy font-bold text-sm rounded-xl hover:brightness-110 transition-all disabled:opacity-50 shadow-lg shadow-brand-lime/20"
          >
            {checking ? <Loader2 className="w-4 h-4 animate-spin" /> : <PlusCircle className="w-4 h-4" />}
            Create Workspace
          </button>
        </div>
      </div>

      {/* ── Plan status strip ────────────────────────────────────────────── */}
      {!entLoading && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard icon={Sparkles} label="Active Plan" value={planDef.displayName} tint={planTint} />
          <StatCard
            icon={Layers}
            label="Workspaces"
            value={`${ownedCount}/${planDef.unlimitedMasterLeagues ? '∞' : planDef.maxMasterLeagues}`}
            tint="#38BDF8"
          />
          <StatCard icon={Network} label="Created" value={created.length} tint="#B8E928" />
          <StatCard icon={Users} label="Joined" value={joined.length} tint="#F59E0B" />
        </div>
      )}

      {!canCreate && !entLoading && (
        <div className="bg-amber-500/10 border border-amber-500/25 text-amber-300 p-4 rounded-2xl text-sm">
          You've reached your {planDef.displayName} plan's workspace limit. Upgrade your plan on the Create screen to add more.
        </div>
      )}

      {error && (
        <div className="bg-brand-red/10 border border-brand-red/30 text-brand-red p-4 rounded-2xl text-sm">
          Error loading workspaces: {error}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-24">
          <Loader2 className="w-9 h-9 text-brand-lime animate-spin" />
        </div>
      ) : (
        <>
          <section className="space-y-4">
            <SectionLabel label="Created by You" tint="#B8E928" />
            {created.length === 0 ? (
              <PanelCard>
                <div className="text-center py-8">
                  <Network className="w-12 h-12 text-gray-700 mx-auto mb-3" />
                  <p className="text-sm text-gray-500">You haven't created any organizer workspace yet.</p>
                </div>
              </PanelCard>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">{created.map(renderCard)}</div>
            )}
          </section>

          <section className="space-y-4">
            <SectionLabel label="Joined Workspaces" tint="#F59E0B" />
            {joined.length === 0 ? (
              <PanelCard>
                <div className="text-center py-8">
                  <Users className="w-12 h-12 text-gray-700 mx-auto mb-3" />
                  <p className="text-sm text-gray-500">You haven't joined any organizer workspace yet.</p>
                </div>
              </PanelCard>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">{joined.map(renderCard)}</div>
            )}
          </section>
        </>
      )}
    </div>
  );
}

function SectionLabel({ label, tint }: { label: string; tint: string }) {
  return (
    <div className="flex items-center gap-2 px-1">
      <div className="w-1.5 h-1.5 rounded-full" style={{ background: tint }} />
      <h2 className="text-xs font-black uppercase tracking-widest text-gray-400">{label}</h2>
      <div className="flex-1 h-px bg-[#1E293B]" />
    </div>
  );
}
