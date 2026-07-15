'use client';

import { useSearchParams } from 'next/navigation';
import { useGlobalSearch } from '@/hooks/useGlobalSearch';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Search as SearchIcon, Trophy, Network } from 'lucide-react';
import Link from 'next/link';
import { Suspense } from 'react';

// Wrap the actual search logic in a component to use useSearchParams safely with Suspense
function SearchContent() {
  const searchParams = useSearchParams();
  const q = searchParams.get('q') || '';
  const { leagues, masterLeagues, loading, error } = useGlobalSearch(q);

  if (!q) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-gray-500">
        <SearchIcon className="w-16 h-16 mb-4 opacity-50" />
        <h2 className="text-xl font-bold">Type to start searching</h2>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-white mb-1">Search Results for "{q}"</h1>
        <p className="text-gray-400 text-sm">Found {leagues.length + masterLeagues.length} results</p>
      </div>

      {loading && (
        <div className="flex justify-center py-10"><Loader2 className="w-8 h-8 text-brand-lime animate-spin" /></div>
      )}

      {error && (
        <div className="p-4 bg-brand-red/20 text-brand-red rounded-xl border border-brand-red">{error}</div>
      )}

      {!loading && leagues.length === 0 && masterLeagues.length === 0 && !error && (
        <Glass className="p-10 text-center text-gray-400">
          No matches found for "{q}". Try a different spelling.
        </Glass>
      )}

      {/* Master Leagues Results */}
      {masterLeagues.length > 0 && (
        <section>
          <h2 className="text-lg font-bold text-white mb-4 flex items-center gap-2 border-b border-white/10 pb-2">
            <Network className="w-5 h-5 text-[#38BDF8]" /> Organizers & Hubs
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {masterLeagues.map((workspace) => (
              <Link href={`/master-leagues/${workspace.id}`} key={workspace.id}>
                <Glass className="p-4 hover:bg-white/5 transition-colors flex items-center gap-4">
                  <div className="w-12 h-12 bg-brand-surfaceDark rounded-xl overflow-hidden shrink-0">
                    {workspace.organizerProfile?.logoUrl ? (
                      <img src={workspace.organizerProfile.logoUrl} className="w-full h-full object-cover" alt="" />
                    ) : (
                      <Network className="w-6 h-6 m-auto text-gray-500 mt-3" />
                    )}
                  </div>
                  <div>
                    <h3 className="font-bold text-white">{workspace.name}</h3>
                    <p className="text-xs text-gray-400">{workspace.followersCount || 0} followers</p>
                  </div>
                </Glass>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* Leagues Results */}
      {leagues.length > 0 && (
        <section>
          <h2 className="text-lg font-bold text-white mb-4 flex items-center gap-2 border-b border-white/10 pb-2">
            <Trophy className="w-5 h-5 text-brand-lime" /> Tournaments & Leagues
          </h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {leagues.map((league) => (
              <Link href={`/leagues/${league.id}`} key={league.id}>
                <Glass className="p-4 hover:bg-white/5 transition-colors flex items-center gap-4 border-l-2 border-l-brand-lime">
                  <div className="w-12 h-12 bg-brand-surfaceDark rounded-xl overflow-hidden shrink-0">
                    {league.coverImageUrl ? (
                      <img src={league.coverImageUrl} className="w-full h-full object-cover" alt="" />
                    ) : (
                      <Trophy className="w-6 h-6 m-auto text-gray-500 mt-3" />
                    )}
                  </div>
                  <div>
                    <h3 className="font-bold text-white">{league.name}</h3>
                    <p className="text-xs text-brand-lime uppercase tracking-wider">{league.status}</p>
                  </div>
                </Glass>
              </Link>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

export default function SearchPage() {
  return (
    <Suspense fallback={<div className="flex justify-center p-10"><Loader2 className="w-8 h-8 animate-spin text-brand-lime" /></div>}>
      <SearchContent />
    </Suspense>
  );
}
