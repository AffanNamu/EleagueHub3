'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { getFixturesByDate } from '@/lib/footballHub/footballHubRepository';
import { FootballFixture, isFinishedFixture, isLiveFixture } from '@/lib/footballHub/types';

function dateStripDays(): Date[] {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(today);
    d.setDate(d.getDate() + (i - 3));
    return d;
  });
}

function fmtDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function MatchesTab() {
  const router = useRouter();
  const days = useMemo(() => dateStripDays(), []);
  const [selected, setSelected] = useState<Date>(days[3]);
  const [fixtures, setFixtures] = useState<FootballFixture[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    getFixturesByDate(fmtDate(selected))
      .then((f) => !cancelled && setFixtures(f))
      .catch((e) => !cancelled && setError(e.message || 'Football data temporarily unavailable. Please try again.'))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [selected]);

  const byLeague = useMemo(() => {
    const map = new Map<number, FootballFixture[]>();
    for (const f of fixtures) {
      if (!map.has(f.leagueId)) map.set(f.leagueId, []);
      map.get(f.leagueId)!.push(f);
    }
    return Array.from(map.values());
  }, [fixtures]);

  const today = days[3];

  return (
    <div>
      <div className="flex gap-2 overflow-x-auto pb-2 mb-4">
        {days.map((d) => {
          const isSelected = fmtDate(d) === fmtDate(selected);
          const isToday = fmtDate(d) === fmtDate(today);
          return (
            <button
              key={fmtDate(d)}
              onClick={() => setSelected(d)}
              className={`shrink-0 w-14 h-16 rounded-xl flex flex-col items-center justify-center transition-colors ${
                isSelected ? 'bg-[#BEF264] text-[#0F172A]' : 'bg-[#1E293B]/50 text-gray-300 hover:bg-[#1E293B]'
              }`}
            >
              <span className="text-[10px] font-bold">
                {isToday ? 'Today' : d.toLocaleDateString('en-US', { weekday: 'short' })}
              </span>
              <span className="text-base font-black">{d.getDate()}</span>
            </button>
          );
        })}
      </div>

      {loading && <p className="text-sm text-gray-400">Loading fixtures...</p>}
      {error && <p className="text-sm text-red-400">{error}</p>}
      {!loading && !error && byLeague.length === 0 && (
        <p className="text-sm text-gray-400">No matches on this date.</p>
      )}

      <div className="space-y-4">
        {byLeague.map((group) => {
          const first = group[0];
          return (
            <div key={first.leagueId} className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4">
              <div className="flex items-center gap-2 mb-3">
                {first.leagueLogoUrl && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={first.leagueLogoUrl} alt="" className="w-5 h-5" />
                )}
                <span className="text-xs font-bold text-gray-300">
                  {first.leagueCountry ? `${first.leagueCountry} · ` : ''}
                  {first.leagueName}
                </span>
              </div>
              <div className="divide-y divide-[#1E293B]">
                {group.map((f) => (
                  <FixtureRow key={f.id} fixture={f} onOpenMatch={() => router.push(`/football/match/${f.id}`)} onOpenTeam={(id) => router.push(`/football/team/${id}`)} />
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function FixtureRow({
  fixture,
  onOpenMatch,
  onOpenTeam,
}: {
  fixture: FootballFixture;
  onOpenMatch: () => void;
  onOpenTeam: (teamId: number) => void;
}) {
  const live = isLiveFixture(fixture);
  const finished = isFinishedFixture(fixture);
  const showScore = live || finished;

  let centerLabel: string;
  if (live) centerLabel = fixture.elapsedMinutes != null ? `${fixture.elapsedMinutes}'` : 'LIVE';
  else if (finished) centerLabel = 'FT';
  else centerLabel = fixture.kickoff.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });

  return (
    <div className="flex items-center py-2.5 gap-2">
      <button onClick={() => onOpenTeam(fixture.homeTeamId)} className="flex-1 flex items-center gap-2 min-w-0 text-left">
        {fixture.homeTeamLogoUrl && <img src={fixture.homeTeamLogoUrl} alt="" className="w-5 h-5 shrink-0" />}
        <span className="text-sm font-bold text-white truncate">{fixture.homeTeamName}</span>
      </button>
      <button onClick={onOpenMatch} className="w-14 shrink-0 flex flex-col items-center">
        {showScore && (
          <span className="text-sm font-black text-white">
            {fixture.homeGoals ?? 0} - {fixture.awayGoals ?? 0}
          </span>
        )}
        <span className={`text-[10px] font-bold ${live ? 'text-red-400' : 'text-gray-400'}`}>{centerLabel}</span>
      </button>
      <button onClick={() => onOpenTeam(fixture.awayTeamId)} className="flex-1 flex items-center justify-end gap-2 min-w-0 text-right">
        <span className="text-sm font-bold text-white truncate">{fixture.awayTeamName}</span>
        {fixture.awayTeamLogoUrl && <img src={fixture.awayTeamLogoUrl} alt="" className="w-5 h-5 shrink-0" />}
      </button>
    </div>
  );
}
