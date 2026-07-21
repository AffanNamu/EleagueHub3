'use client';

import { useState } from 'react';
import { useOrganizerDiscovery } from '@/hooks/useOrganizerDiscovery';
import { PanelCard } from '@/components/masterLeagues/PanelCard';
import { Loader2, Network, Search, ShieldCheck, Users, ChevronRight, Compass, BadgeCheck } from 'lucide-react';
import Link from 'next/link';
import { cloudinaryOptimizedUrl } from '@/lib/cloudinary/cloudinaryUpload';

export default function OrganizerDiscoveryScreen() {
  const { hubs, verified, loading } = useOrganizerDiscovery();
  const [search, setSearch] = useState('');

  const filtered = search.trim()
    ? hubs.filter((h) => h.name.toLowerCase().includes(search.trim().toLowerCase()))
    : hubs;

  return (
    <div className="max-w-7xl mx-auto pb-16 space-y-8">
      <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
        <div className="absolute -top-40 left-1/3 w-[500px] h-[500px] rounded-full bg-[#38BDF8]/[0.05] blur-[120px]" />
        <div className="absolute top-60 right-1/4 w-[400px] h-[400px] rounded-full bg-brand-lime/[0.05] blur-[120px]" />
      </div>

      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-11 h-11 rounded-xl bg-[#38BDF8]/10 border border-[#38BDF8]/25 flex items-center justify-center">
            <Compass className="w-5 h-5 text-[#38BDF8]" />
          </div>
          <div>
            <h1 className="text-2xl md:text-3xl font-black text-white tracking-tight">Organizer Discovery</h1>
            <p className="text-gray-500 text-sm mt-0.5">Find top-rated eSports hubs and communities.</p>
          </div>
        </div>

        <div className="relative w-full md:w-72">
          <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 text-gray-500 w-4 h-4" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search organizers..."
            className="w-full pl-10 pr-4 py-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl text-sm text-white placeholder:text-gray-600 focus:outline-none focus:border-[#38BDF8]/50 transition-colors"
          />
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-24">
          <Loader2 className="w-9 h-9 animate-spin text-[#38BDF8]" />
        </div>
      ) : (
        <>
          {verified.length > 0 && (
            <section className="space-y-4">
              <SectionLabel icon={BadgeCheck} label="Verified Organizers" tint="#F59E0B" />
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                {verified.map((ml) => (
                  <HubCard key={ml.id} ml={ml} />
                ))}
              </div>
            </section>
          )}

          <section className="space-y-4">
            <SectionLabel icon={Network} label="All Organizers" tint="#38BDF8" />
            {filtered.length === 0 ? (
              <PanelCard>
                <div className="text-center py-10">
                  <Network className="w-14 h-14 text-gray-700 mx-auto mb-4" />
                  <h3 className="text-lg font-bold text-white">No Hubs Found</h3>
                  <p className="text-sm text-gray-500 mt-1">Try a different search term.</p>
                </div>
              </PanelCard>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                {filtered.map((ml) => (
                  <HubCard key={ml.id} ml={ml} />
                ))}
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}

function SectionLabel({ icon: Icon, label, tint }: { icon: any; label: string; tint: string }) {
  return (
    <div className="flex items-center gap-2">
      <Icon className="w-4 h-4" style={{ color: tint }} />
      <h2 className="text-sm font-black uppercase tracking-widest text-gray-300">{label}</h2>
      <div className="flex-1 h-px bg-[#1E293B]" />
    </div>
  );
}

function HubCard({ ml }: { ml: ReturnType<typeof useOrganizerDiscovery>['hubs'][number] }) {
  // Corrected Plan Colors
  const planTint = ml.plan === 'elite' ? '#F59E0B' : ml.plan === 'pro' ? '#38BDF8' : '#B8E928';

  return (
    <Link href={`/master-leagues/${ml.id}`}>
      <div className="bg-[#0B1221] border border-[#1E293B] hover:border-[#2A3A52] rounded-2xl p-5 transition-all group relative overflow-hidden shadow-lg">
        <div
          className="absolute -top-10 -right-10 w-32 h-32 rounded-full blur-3xl opacity-0 group-hover:opacity-[0.08] transition-opacity"
          style={{ background: planTint }}
        />
        <div className="relative flex items-center gap-4 mb-4">
          <div className="w-14 h-14 bg-[#070B14] border border-[#1E293B] rounded-xl overflow-hidden shrink-0 flex items-center justify-center">
            {ml.organizerProfile.logoUrl ? (
              <img
                src={cloudinaryOptimizedUrl(ml.organizerProfile.logoUrl, { width: 200, height: 200, crop: 'fill' })}
                className="w-full h-full object-cover"
                alt=""
              />
            ) : (
              <Network className="w-6 h-6 text-gray-600" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="font-bold text-white text-base group-hover:text-brand-lime transition-colors truncate">
              {ml.name}
            </h3>
            {ml.verifiedBadge && (
              <span className="flex items-center gap-1 text-[10px] text-[#F59E0B] font-bold uppercase tracking-wider mt-0.5">
                <BadgeCheck className="w-3 h-3 text-[#FEF08A] fill-[#F59E0B]" /> Verified
              </span>
            )}
          </div>
        </div>

        <p className="relative text-sm text-gray-500 line-clamp-2 mb-4 h-10 leading-relaxed">
          {ml.organizerProfile.bio || 'No description provided.'}
        </p>

        <div className="relative flex items-center justify-between pt-4 border-t border-[#1E293B]">
          <span className="flex items-center gap-1.5 text-xs font-bold text-gray-500">
            <Users className="w-3.5 h-3.5" />
            {ml.followersCount} Followers
          </span>
          <span className="flex items-center gap-1 text-xs text-brand-lime font-bold group-hover:gap-2 transition-all">
            View <ChevronRight className="w-3.5 h-3.5" />
          </span>
        </div>
      </div>
    </Link>
  );
}
