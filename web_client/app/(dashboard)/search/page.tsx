'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { onAuthStateChanged } from 'firebase/auth';
import { searchUsersWeb, fetchNearbyTeamsWeb, UserSearchEntry } from '@/lib/search/userSearchRepository';
import { checkRelationshipStatusWeb, toggleFollowWeb } from '@/lib/profile/teamProfileRepository';
import { resolveCountryCodeWeb } from '@/lib/countryResolver';
import { Glass } from '@/components/ui/Glass';
import { Search, Loader2, X, Globe, User } from 'lucide-react';

export default function UserSearchScreen() {
  const [authUid, setAuthUid] = useState<string>('');
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  
  const [results, setResults] = useState<UserSearchEntry[]>([]);
  const [searching, setSearching] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);

  const [nearby, setNearby] = useState<UserSearchEntry[]>([]);
  const [nearbyLoading, setNearbyLoading] = useState(true);
  const [nearbyCountry, setNearbyCountry] = useState('');

  const debounceTimeout = useRef<NodeJS.Timeout | null>(null);

  // Auth Listener
  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => setAuthUid(u?.uid || ''));
    return () => unsub();
  }, []);

  // Fetch Nearby on Mount
  useEffect(() => {
    async function loadNearby() {
      if (!authUid) return;
      try {
        // FIXED: this used to hardcode 'US', so every web user saw US
        // teams under "Teams Near You" regardless of where they actually
        // are — while the Flutter app resolves this via
        // CountryResolverService.instance.resolveCountryCode(). Now uses
        // the same class of IP-geolocation lookup so both platforms show
        // a consistent "nearby" set for the same signed-in user.
        const cc = await resolveCountryCodeWeb();
        setNearbyCountry(cc);
        const data = await fetchNearbyTeamsWeb(cc, authUid);
        setNearby(data);
      } catch (err) {
        console.error(err);
      } finally {
        setNearbyLoading(false);
      }
    }
    if (authUid) loadNearby();
  }, [authUid]);

  // Handle Input with Debounce (350ms to match Flutter)
  const handleQueryChange = (val: string) => {
    setQuery(val);
    if (debounceTimeout.current) clearTimeout(debounceTimeout.current);

    if (val.trim() === '') {
      setResults([]);
      setHasSearched(false);
      setSearching(false);
      return;
    }

    debounceTimeout.current = setTimeout(() => {
      setDebouncedQuery(val.trim());
    }, 350);
  };

  // Run Search when Debounced Query Changes
  useEffect(() => {
    async function runSearch() {
      if (!debouncedQuery) return;
      setSearching(true);
      setHasSearched(true);
      try {
        const data = await searchUsersWeb(debouncedQuery, authUid);
        setResults(data);
      } catch (err) {
        console.error(err);
      } finally {
        setSearching(false);
      }
    }
    runSearch();
  }, [debouncedQuery, authUid]);

  const showManualSearch = hasSearched;

  return (
    <div className="max-w-3xl mx-auto space-y-6 pb-20 px-4 sm:px-6 mt-4">
      <div className="relative">
        <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-500" />
        <input 
          value={query}
          onChange={(e) => handleQueryChange(e.target.value)}
          placeholder="Search by team name or @username..." 
          className="w-full bg-[#0B1221] border border-[#1E293B] rounded-2xl py-4 pl-12 pr-12 text-white font-bold outline-none focus:border-[#BEF264] shadow-xl transition-colors"
        />
        {query && (
          <button onClick={() => handleQueryChange('')} className="absolute right-4 top-1/2 -translate-y-1/2 p-1 text-gray-500 hover:text-white transition-colors">
            <X className="w-5 h-5" />
          </button>
        )}
      </div>

      {searching && <div className="h-1 w-full bg-[#1E293B] overflow-hidden rounded-full"><div className="h-full bg-[#BEF264] w-1/3 animate-[slide_1s_ease-in-out_infinite]" /></div>}

      <div className="pt-2">
        {showManualSearch ? (
          // ── Search Results ──
          results.length === 0 && !searching ? (
            <div className="text-center py-10 font-bold text-gray-500">No teams found.</div>
          ) : (
            <div className="space-y-3">
              {results.map(entry => <TeamTile key={entry.userId} entry={entry} authUid={authUid} />)}
            </div>
          )
        ) : (
          // ── Nearby Section ──
          <div>
            <h2 className="text-lg font-black text-white flex items-center gap-2 mb-2">
              <Globe className="w-5 h-5 text-[#BEF264]" /> 
              {nearbyCountry ? `Teams in ${nearbyCountry}` : 'Teams Near You'}
            </h2>
            <p className="text-xs font-semibold text-gray-500 mb-6">Automatically shown based on your region. Use the search box above to find a specific team.</p>
            
            {nearbyLoading ? (
              <div className="flex justify-center py-10"><Loader2 className="w-8 h-8 animate-spin text-[#BEF264]" /></div>
            ) : nearby.length === 0 ? (
              <div className="text-center py-10 font-bold text-gray-500">No nearby teams found yet. Try searching by name or ID.</div>
            ) : (
              <div className="space-y-3">
                {nearby.map(entry => <TeamTile key={entry.userId} entry={entry} authUid={authUid} />)}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Interactive Tile Component ──
function TeamTile({ entry, authUid }: { entry: UserSearchEntry; authUid: string }) {
  const router = useRouter();
  const [following, setFollowing] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);

  const isSelf = authUid === entry.userId;

  useEffect(() => {
    async function checkFollow() {
      if (isSelf || !authUid) return;
      const rel = await checkRelationshipStatusWeb(authUid, entry.userId);
      setFollowing(rel.following);
    }
    checkFollow();
  }, [entry.userId, authUid, isSelf]);

  const handleToggleFollow = async (e: React.MouseEvent) => {
    e.stopPropagation(); // Prevent routing to profile
    if (busy || following === null || !authUid) return;
    
    const prev = following;
    setBusy(true);
    setFollowing(!prev); // Optimistic UI update

    try {
      await toggleFollowWeb(authUid, entry.userId, prev);
    } catch (err) {
      setFollowing(prev); // Revert on failure
      alert("Failed to update follow status");
    } finally {
      setBusy(false);
    }
  };

  const gameLabel = entry.game.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase());

  return (
    <Glass 
      onClick={() => router.push(`/profile/${entry.userId}`)}
      className="p-4 flex items-center justify-between border-[#1E293B] bg-[#0B1221] hover:bg-white/5 hover:border-white/10 transition-colors cursor-pointer rounded-2xl group"
    >
      <div className="flex items-center gap-4">
        <div className="w-12 h-12 rounded-full bg-[#1E293B] border border-white/5 shrink-0 overflow-hidden flex items-center justify-center">
          {entry.avatarUrl ? <img src={entry.avatarUrl} className="w-full h-full object-cover" /> : <User className="w-6 h-6 text-gray-500" />}
        </div>
        <div>
          <h3 className="font-black text-white text-base group-hover:text-[#BEF264] transition-colors line-clamp-1">{entry.displayName || 'Unnamed Team'}</h3>
          <p className="text-xs font-semibold text-gray-500">
            {entry.game ? `${gameLabel} • ` : ''}#{entry.shareId}
          </p>
        </div>
      </div>

      {!isSelf && following !== null && (
        <button 
          onClick={handleToggleFollow} disabled={busy}
          className={`px-4 py-2 rounded-full text-xs font-black transition-all ${following ? 'bg-transparent text-white border border-[#1E293B] hover:bg-white/10' : 'bg-[#BEF264] text-[#0F172A] hover:brightness-110 shadow-lg shadow-[#BEF264]/20'}`}
        >
          {busy ? <Loader2 className="w-3 h-3 animate-spin mx-auto" /> : (following ? 'Following' : 'Follow')}
        </button>
      )}
    </Glass>
  );
}
