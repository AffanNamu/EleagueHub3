'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { ArrowLeft } from 'lucide-react';
import { getStandings, currentFootballSeasonGuess } from '@/lib/footballHub/footballHubRepository';
import { FootballStandingsTable, FootballStandingRow } from '@/lib/footballHub/types';

export default function StandingsPage() {
  const params = useParams<{ leagueId: string }>();
  const searchParams = useSearchParams();
  const router = useRouter();
  const leagueId = parseInt(params.leagueId, 10);
  const season = parseInt(searchParams.get('season') || '', 10) || currentFootballSeasonGuess();

  const [table, setTable] = useState<FootballStandingsTable | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    getStandings(leagueId, season)
      .then((t) => !cancelled && setTable(t))
      .catch((e) => !cancelled && setError(e.message || 'Football data temporarily unavailable. Please try again.'))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [leagueId, season]);

  return (
    <div className="min-h-screen bg-[#070B14] pb-20 md:pb-8">
      <div className="max-w-7xl mx-auto">
        <button onClick={() => router.back()} className="flex items-center gap-2 text-gray-400 hover:text-white mb-4 text-sm font-bold">
          <ArrowLeft className="w-4 h-4" /> Back
        </button>

        {loading && <p className="text-sm text-gray-400">Loading standings...</p>}
        {error && <p className="text-sm text-red-400">{error}</p>}
        {!loading && !error && (!table || table.groups.length === 0) && (
          <p className="text-sm text-gray-400">No standings available yet.</p>
        )}

        {table && (
          <div className="flex items-center gap-3 mb-6">
            {table.leagueLogoUrl && <img src={table.leagueLogoUrl} alt="" className="w-8 h-8" />}
            <h1 className="text-xl font-black text-white">{table.leagueName}</h1>
          </div>
        )}

        {table?.groups.map((rows, i) => (
          <div key={i} className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 mb-4">
            <div className="grid grid-cols-[24px_1fr_32px_32px_40px] gap-2 text-[11px] font-bold text-gray-500 px-2 pb-2">
              <span>#</span>
              <span>TEAM</span>
              <span className="text-center">P</span>
              <span className="text-center">GD</span>
              <span className="text-center">PTS</span>
            </div>
            {rows.map((r) => (
              <StandingRow key={r.teamId} row={r} onClick={() => router.push(`/football/team/${r.teamId}`)} />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

function StandingRow({ row, onClick }: { row: FootballStandingRow; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full grid grid-cols-[24px_1fr_32px_32px_40px] gap-2 items-center px-2 py-2.5 text-left hover:bg-[#1E293B]/30 rounded-lg transition-colors"
    >
      <span className="text-sm font-bold text-white">{row.rank}</span>
      <span className="flex items-center gap-2 min-w-0">
        {row.teamLogoUrl && <img src={row.teamLogoUrl} alt="" className="w-5 h-5 shrink-0" />}
        <span className="text-sm font-bold text-white truncate">{row.teamName}</span>
      </span>
      <span className="text-center text-sm text-gray-400">{row.played}</span>
      <span className="text-center text-sm text-gray-400">{row.goalsDiff > 0 ? `+${row.goalsDiff}` : row.goalsDiff}</span>
      <span className="text-center text-sm font-black text-white">{row.points}</span>
    </button>
  );
}
