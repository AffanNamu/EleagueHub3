'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { useKnockoutMatches } from '@/hooks/useKnockoutMatches';
import { useLeagueTeams } from '@/hooks/useLeagueTeams';
import { Glass } from '@/components/ui/Glass';
import { KnockoutCard } from '@/components/leagues/KnockoutCard';
import { ArrowLeft, Loader2, GitMerge, ChevronLeft, ChevronRight } from 'lucide-react';
import { cn } from '@/lib/utils';

export default function KnockoutScreen() {
  const params = useParams();
  const router = useRouter();
  const leagueId = params.id as string;

  const { matches, loading: matchesLoading } = useKnockoutMatches(leagueId);
  const { teams, loading: teamsLoading } = useLeagueTeams(leagueId);

  // useKnockoutMatches already sorts matches into round order (Play-off,
  // Round of 64, Round of 32, ... Final, 3rd Place) — dedupe while
  // preserving that order rather than re-deriving it here.
  const rounds = Array.from(new Set(matches.map((m) => m.roundName)));

  const [selectedRound, setSelectedRound] = useState<string | null>(null);

  // Land on the first round with an unplayed match (i.e. "what's live
  // right now"), falling back to the first round — recomputed whenever
  // the round list actually changes shape, not on every match update
  // (which would yank the user back after they've picked a round to
  // review results in).
  useEffect(() => {
    if (rounds.length === 0) return;
    const firstUnfinished = rounds.find((r) =>
      matches.some((m) => m.roundName === r && m.status !== 'played' && m.status !== 'completed'),
    );
    setSelectedRound(firstUnfinished ?? rounds[0]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rounds.join('|')]);

  if (matchesLoading || teamsLoading) {
    return <div className="flex justify-center py-20"><Loader2 className="w-10 h-10 text-brand-lime animate-spin" /></div>;
  }

  const getTeam = (teamId: string) => teams.find(t => t.id === teamId);

  const activeRound = selectedRound ?? rounds[0] ?? '';
  const activeRoundIndex = Math.max(0, rounds.indexOf(activeRound));

  return (
    <div className="space-y-6">

      {/* SVG Bracket Lines CSS Setup — desktop tree view only */}
      <style dangerouslySetInnerHTML={{__html: `
        .no-scrollbar::-webkit-scrollbar { display: none; }
        .no-scrollbar { scrollbar-width: none; -ms-overflow-style: none; }
        .bracket-col { position: relative; }
        .bracket-col:not(:last-child)::after {
          content: '';
          position: absolute;
          top: 0; right: -24px; bottom: 0; width: 24px;
        }
        .bracket-match { position: relative; }
        .bracket-match::after {
          content: '';
          position: absolute;
          right: -24px;
          top: 50%;
          width: 24px;
          border-bottom: 2px solid rgba(255,255,255,0.1);
        }
        .bracket-col:not(:last-child) .bracket-match:nth-child(odd)::before {
          content: '';
          position: absolute;
          right: -24px;
          top: 50%;
          height: 100%; /* Spans to the next match */
          border-right: 2px solid rgba(255,255,255,0.1);
        }
      `}} />

      {/* Header */}
      <div className="flex items-center gap-4">
        <button
          onClick={() => router.back()}
          className="p-2 bg-brand-surface hover:bg-white/10 rounded-xl transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <div>
          <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
            <GitMerge className="w-6 h-6 text-brand-lime" />
            Tournament Bracket
          </h1>
          <p className="text-gray-400 mt-1">Knockout phase live tracking</p>
        </div>
      </div>

      {matches.length === 0 ? (
        <Glass className="p-10 text-center flex flex-col items-center">
          <GitMerge className="w-16 h-16 text-gray-500 mb-4" />
          <h3 className="text-xl font-semibold text-white">No Bracket Generated</h3>
          <p className="text-gray-400 mt-2">The knockout phase hasn&apos;t been drawn yet.</p>
        </Glass>
      ) : (
        <>
          {/* ── Narrow viewports: round selector + single-column match list ── */}
          <div className="md:hidden space-y-4">
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setSelectedRound(rounds[Math.max(0, activeRoundIndex - 1)])}
                disabled={activeRoundIndex <= 0}
                className="p-2 rounded-lg bg-brand-surface border border-white/10 text-white disabled:opacity-30 shrink-0"
                aria-label="Previous round"
              >
                <ChevronLeft className="w-4 h-4" />
              </button>

              <div className="flex-1 overflow-x-auto no-scrollbar">
                <div className="flex gap-2 w-max">
                  {rounds.map((round) => (
                    <button
                      key={round}
                      type="button"
                      onClick={() => setSelectedRound(round)}
                      className={cn(
                        'px-3 py-2 rounded-lg text-xs font-black uppercase tracking-wide whitespace-nowrap transition-colors border',
                        round === activeRound
                          ? 'bg-brand-lime text-black border-brand-lime'
                          : 'bg-brand-surface text-gray-400 border-white/10',
                      )}
                    >
                      {round}
                    </button>
                  ))}
                </div>
              </div>

              <button
                type="button"
                onClick={() => setSelectedRound(rounds[Math.min(rounds.length - 1, activeRoundIndex + 1)])}
                disabled={activeRoundIndex >= rounds.length - 1}
                className="p-2 rounded-lg bg-brand-surface border border-white/10 text-white disabled:opacity-30 shrink-0"
                aria-label="Next round"
              >
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>

            <div className="flex flex-col items-center gap-3">
              {matches.filter((m) => m.roundName === activeRound).map((match) => (
                <KnockoutCard key={match.id} match={match} getTeam={getTeam} />
              ))}
            </div>
          </div>

          {/* ── Wide viewports: full horizontal bracket tree ── */}
          <Glass className="hidden md:block p-4 md:p-8 overflow-x-auto">
            <div className="flex gap-12 min-w-max pb-8">
              {rounds.map(round => (
                <div key={round} className="bracket-col flex flex-col gap-8 justify-around min-h-[500px]">
                  <h3 className="text-center font-black text-gray-500 tracking-widest uppercase mb-4">{round}</h3>

                  <div className="flex flex-col gap-6 justify-around flex-1">
                    {matches.filter(m => m.roundName === round).map(match => (
                      <div key={match.id} className="bracket-match relative group">
                        <KnockoutCard match={match} getTeam={getTeam} />
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </Glass>
        </>
      )}
    </div>
  );
}
