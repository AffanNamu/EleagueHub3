'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Search, ChevronRight, Shield } from 'lucide-react';
import {
  POPULAR_LEAGUES,
  currentFootballSeasonGuess,
  searchLeagues,
} from '@/lib/footballHub/footballHubRepository';
import { FootballLeagueInfo } from '@/lib/footballHub/types';

export function LeaguesTab() {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<FootballLeagueInfo[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const season = currentFootballSeasonGuess();

  async function runSearch(q: string) {
    setQuery(q);
    if (q.trim().length < 3) {
      setResults(null);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const r = await searchLeagues(q.trim());
      setResults(r);
    } catch (e: any) {
      setError(e.message || 'Football data temporarily unavailable. Please try again.');
    } finally {
      setLoading(false);
    }
  }

  function openStandings(leagueId: number, leagueSeason: number) {
    router.push(`/football/standings/${leagueId}?season=${leagueSeason}`);
  }

  return (
    <div>
      <div className="relative mb-5">
        <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-gray-500" />
        <input
          value={query}
          onChange={(e) => runSearch(e.target.value)}
          placeholder="Search leagues (3+ letters)"
          className="w-full h-11 pl-10 pr-4 rounded-xl bg-[#1E293B]/50 border border-[#1E293B] text-white text-sm placeholder:text-gray-500 focus:outline-none focus:border-[#BEF264]/50"
        />
      </div>

      {loading && <p className="text-sm text-gray-400">Searching...</p>}
      {error && <p className="text-sm text-red-400">{error}</p>}

      {results ? (
        <div className="space-y-2">
          {results.length === 0 && !loading && <p className="text-sm text-gray-400">No leagues found.</p>}
          {results.map((l) => (
            <LeagueRow
              key={l.id}
              name={l.name}
              subtitle={l.countryName}
              logoUrl={l.logoUrl}
              onClick={l.currentSeason > 0 ? () => openStandings(l.id, l.currentSeason) : undefined}
            />
          ))}
        </div>
      ) : (
        <>
          <p className="text-xs font-bold text-gray-400 mb-2">Popular competitions</p>
          <div className="space-y-2">
            {POPULAR_LEAGUES.map((l) => (
              <LeagueRow key={l.id} name={l.name} onClick={() => openStandings(l.id, season)} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function LeagueRow({
  name,
  subtitle,
  logoUrl,
  onClick,
}: {
  name: string;
  subtitle?: string;
  logoUrl?: string;
  onClick?: () => void;
}) {
  return (
    <button
      onClick={onClick}
      disabled={!onClick}
      className="w-full flex items-center gap-3 bg-[#0B1221] border border-[#1E293B] rounded-xl px-4 py-3 text-left hover:border-[#BEF264]/30 transition-colors disabled:opacity-60"
    >
      {logoUrl ? (
        <img src={logoUrl} alt="" className="w-7 h-7 rounded" />
      ) : (
        <div className="w-7 h-7 rounded bg-[#1E293B] flex items-center justify-center">
          <Shield className="w-4 h-4 text-gray-400" />
        </div>
      )}
      <div className="flex-1 min-w-0">
        <p className="text-sm font-bold text-white truncate">{name}</p>
        {subtitle && <p className="text-xs text-gray-400 truncate">{subtitle}</p>}
      </div>
      <ChevronRight className="w-4 h-4 text-gray-500 shrink-0" />
    </button>
  );
}
