'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { MasterLeague } from '@/types/masterLeague';
import {
  discoverFeatured,
  discoverVerified,
  discoverRecentActive,
  discoverNearby,
  fetchWorkspaceByUsername,
} from '@/lib/masterLeagues/masterLeaguesRepository';
import { resolveCountryCodeWeb } from '@/lib/countryResolver';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Globe, Search, Star, ShieldCheck, Zap, Network as Hub, X } from 'lucide-react';

export default function OrganizerDiscoveryScreen() {
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [searchResult, setSearchResult] = useState<MasterLeague | null>(null);
  const [searchError, setSearchError] = useState<string | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [nearby, setNearby] = useState<MasterLeague[]>([]);
  const [nearbyCountry, setNearbyCountry] = useState('');
  const [nearbyLoading, setNearbyLoading] = useState(true);

  const [featured, setFeatured] = useState<MasterLeague[]>([]);
  const [featuredLoading, setFeaturedLoading] = useState(true);

  const [verified, setVerified] = useState<MasterLeague[]>([]);
  const [verifiedLoading, setVerifiedLoading] = useState(true);

  const [recent, setRecent] = useState<MasterLeague[]>([]);
  const [recentLoading, setRecentLoading] = useState(true);

  useEffect(() => {
    discoverFeatured(8).then(setFeatured).finally(() => setFeaturedLoading(false));
    discoverVerified(12).then(setVerified).finally(() => setVerifiedLoading(false));
    discoverRecentActive(12).then(setRecent).finally(() => setRecentLoading(false));

    (async () => {
      setNearbyLoading(true);
      const cc = await resolveCountryCodeWeb();
      setNearbyCountry(cc);
      const data = await discoverNearby(cc, 12);
      setNearby(data);
      setNearbyLoading(false);
    })();
  }, []);

  function handleQueryChange(value: string) {
    setQuery(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);

    if (!value.trim()) {
      setHasSearched(false);
      setSearchResult(null);
      setSearchError(null);
      return;
    }

    debounceRef.current = setTimeout(() => runSearch(value.trim()), 450);
  }

  async function runSearch(term: string) {
    setSearching(true);
    setHasSearched(true);
    setSearchError(null);
    try {
      const result = await fetchWorkspaceByUsername(term);
      setSearchResult(result);
      setSearchError(result ? null : 'No organizer found for that username.');
    } catch {
      setSearchError('Something went wrong. Please try again.');
    } finally {
      setSearching(false);
    }
  }

  return (
    <div className="max-w-6xl mx-auto space-y-8 pb-20 px-4 sm:px-6">
      <div className="mt-6 mb-8 text-center">
        <div className="w-16 h-16 bg-[#38BDF8]/10 rounded-full flex items-center justify-center mx-auto mb-4 border border-[#38BDF8]/20">
          <Globe className="w-8 h-8 text-[#38BDF8]" />
        </div>
        <h1 className="text-3xl font-black text-white">Organizer Discovery</h1>
        <p className="text-gray-400 mt-2 font-medium">Find official brands, verified workspaces, and active communities.</p>
      </div>

      <div className="relative max-w-xl mx-auto">
        <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-500" />
        <input
          value={query}
          onChange={(e) => handleQueryChange(e.target.value)}
          placeholder="Search organizer by @username..."
          className="w-full bg-[#0B1221] border border-[#1E293B] rounded-2xl py-4 pl-12 pr-12 text-white font-bold outline-none focus:border-[#38BDF8] shadow-xl"
        />
        {query && (
          <button onClick={() => handleQueryChange('')} className="absolute right-4 top-1/2 -translate-y-1/2 p-1 text-gray-500 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        )}
      </div>

      {hasSearched && (
        <div className="max-w-xl mx-auto">
          {searching ? (
            <div className="flex justify-center py-6"><Loader2 className="w-6 h-6 animate-spin text-[#38BDF8]" /></div>
          ) : searchResult ? (
            <OrganizerCard ml={searchResult} />
          ) : (
            searchError && <p className="text-center text-gray-500 font-semibold py-4">{searchError}</p>
          )}
        </div>
      )}

      <DiscoverySection
        icon={<Globe className="w-5 h-5 text-[#BEF264]" />}
        title={nearbyCountry ? `Organizers in ${nearbyCountry}` : 'Organizers Near You'}
        loading={nearbyLoading}
        items={nearby}
        emptyText="No organizers found in your region yet."
      />

      <DiscoverySection
        icon={<Star className="w-5 h-5 text-amber-400" />}
        title="Featured Organizers"
        loading={featuredLoading}
        items={featured}
        emptyText="No featured organizers right now."
      />

      <DiscoverySection
        icon={<ShieldCheck className="w-5 h-5 text-sky-400" />}
        title="Verified Organizers"
        loading={verifiedLoading}
        items={verified}
        emptyText="No verified organizers yet."
      />

      <DiscoverySection
        icon={<Zap className="w-5 h-5 text-[#BEF264]" />}
        title="Recently Active"
        loading={recentLoading}
        items={recent}
        emptyText="No active organizers yet."
      />
    </div>
  );
}

function DiscoverySection({
  icon, title, loading, items, emptyText,
}: {
  icon: React.ReactNode; title: string; loading: boolean; items: MasterLeague[]; emptyText: string;
}) {
  return (
    <div>
      <h2 className="text-lg font-black text-white flex items-center gap-2 border-b border-[#1E293B] pb-2 mb-6">
        {icon} {title}
      </h2>

      {loading ? (
        <div className="flex justify-center py-10"><Loader2 className="w-8 h-8 animate-spin text-[#BEF264]" /></div>
      ) : items.length === 0 ? (
        <p className="text-center text-gray-500 font-bold py-10">{emptyText}</p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {items.map((ml) => <OrganizerCard key={ml.id} ml={ml} />)}
        </div>
      )}
    </div>
  );
}

function OrganizerCard({ ml }: { ml: MasterLeague }) {
  return (
    <Link href={`/master-leagues/${ml.id}`}>
      <Glass className="p-5 hover:bg-white/5 transition-colors border-[#1E293B] hover:border-white/10 group cursor-pointer h-full flex flex-col bg-[#0B1221]">
        <div className="flex items-center gap-4 mb-4">
          <div className="w-14 h-14 rounded-full bg-[#1E293B] overflow-hidden shrink-0 border border-white/5">
            {ml.organizerProfile.logoUrl ? (
              <img src={ml.organizerProfile.logoUrl} alt={ml.name} className="w-full h-full object-cover" />
            ) : (
              <Hub className="w-6 h-6 m-auto mt-4 text-gray-500" />
            )}
          </div>
          <div>
            <h3 className="font-black text-white text-lg group-hover:text-[#38BDF8] transition-colors line-clamp-1">{ml.name || 'Organizer'}</h3>
            {ml.verifiedBadge && <span className="text-[10px] font-black text-sky-400 uppercase tracking-widest">Verified</span>}
          </div>
        </div>
        <div className="mt-auto pt-4 border-t border-[#1E293B] flex items-center justify-between text-[10px] font-black uppercase tracking-widest text-gray-500">
          <span>{ml.followersCount || 0} Followers</span>
          <span>{ml.analytics.totalTournamentsCreated || 0} Events</span>
        </div>
      </Glass>
    </Link>
  );
}
