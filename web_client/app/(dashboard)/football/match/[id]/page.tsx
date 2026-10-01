'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { ArrowLeft, Shield, Square, SquareCheckBig, Users } from 'lucide-react';
import { getFixtureById, getFixtureEvents } from '@/lib/footballHub/footballHubRepository';
import { FootballFixture, FootballMatchEvent, isFinishedFixture, isLiveFixture, isUpcomingFixture } from '@/lib/footballHub/types';

export default function MatchPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const fixtureId = parseInt(params.id, 10);

  const [fixture, setFixture] = useState<FootballFixture | null | undefined>(undefined);
  const [events, setEvents] = useState<FootballMatchEvent[] | null>(null);
  const [lastFetchedAt, setLastFetchedAt] = useState<Date | null>(null);
  const [, setTick] = useState(0);

  useEffect(() => {
    getFixtureById(fixtureId).then(setFixture);
  }, [fixtureId]);

  useEffect(() => {
    getFixtureEvents(fixtureId).then((e) => {
      setEvents(e);
      setLastFetchedAt(new Date());
    });
  }, [fixtureId]);

  useEffect(() => {
    const t = setInterval(() => setTick((v) => v + 1), 30000);
    return () => clearInterval(t);
  }, []);

  function agoLabel(): string {
    if (!lastFetchedAt) return '';
    const diffSec = Math.floor((Date.now() - lastFetchedAt.getTime()) / 1000);
    if (diffSec < 60) return `Updated ${diffSec}s ago`;
    if (diffSec < 3600) return `Updated ${Math.floor(diffSec / 60)} min ago`;
    return `Updated ${Math.floor(diffSec / 3600)}h ago`;
  }

  if (fixture === undefined) {
    return (
      <div className="min-h-screen bg-[#070B14] pb-20 md:pb-8">
        <p className="text-sm text-gray-400">Loading...</p>
      </div>
    );
  }

  if (fixture === null) {
    return (
      <div className="min-h-screen bg-[#070B14] pb-20 md:pb-8">
        <p className="text-sm text-gray-400">Football data temporarily unavailable. Please try again.</p>
      </div>
    );
  }

  const live = isLiveFixture(fixture);
  const finished = isFinishedFixture(fixture);
  let statusLabel: string;
  if (live) statusLabel = fixture.elapsedMinutes != null ? `LIVE · ${fixture.elapsedMinutes}'` : 'LIVE';
  else if (finished) statusLabel = 'Full time';
  else statusLabel = fixture.kickoff.toLocaleString('en-US', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

  return (
    <div className="min-h-screen bg-[#070B14] pb-20 md:pb-8">
      <div className="max-w-7xl mx-auto">
        <button onClick={() => router.back()} className="flex items-center gap-2 text-gray-400 hover:text-white mb-4 text-sm font-bold">
          <ArrowLeft className="w-4 h-4" /> Back
        </button>

        <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-6 mb-6">
          <div className="flex items-center justify-between">
            <TeamHeader name={fixture.homeTeamName} logoUrl={fixture.homeTeamLogoUrl} onClick={() => router.push(`/football/team/${fixture.homeTeamId}`)} />
            <div className="flex flex-col items-center shrink-0 px-4">
              <span className="text-2xl font-black text-white">
                {live || finished ? `${fixture.homeGoals ?? 0} - ${fixture.awayGoals ?? 0}` : 'vs'}
              </span>
              <span className={`text-xs font-bold mt-1 ${live ? 'text-red-400' : 'text-gray-400'}`}>{statusLabel}</span>
            </div>
            <TeamHeader name={fixture.awayTeamName} logoUrl={fixture.awayTeamLogoUrl} onClick={() => router.push(`/football/team/${fixture.awayTeamId}`)} />
          </div>
          {fixture.round && <p className="text-xs text-gray-400 text-center mt-4">{fixture.round}</p>}
        </div>

        <div className="flex items-center justify-between mb-2">
          <p className="text-xs font-bold text-gray-400">Match events</p>
          {lastFetchedAt && <p className="text-[11px] text-gray-500">{agoLabel()}</p>}
        </div>

        {events === null && <p className="text-sm text-gray-400">Loading...</p>}
        {events?.length === 0 && (
          <p className="text-sm text-gray-400">
            {isUpcomingFixture(fixture) ? 'Events will appear once the match kicks off.' : 'No events reported for this match.'}
          </p>
        )}

        <div className="space-y-3">
          {events?.map((e, i) => (
            <EventRow key={i} event={e} />
          ))}
        </div>
      </div>
    </div>
  );
}

function TeamHeader({ name, logoUrl, onClick }: { name: string; logoUrl: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex-1 flex flex-col items-center gap-2 text-center">
      {logoUrl ? (
        <img src={logoUrl} alt="" className="w-10 h-10" />
      ) : (
        <div className="w-10 h-10 rounded bg-[#1E293B] flex items-center justify-center">
          <Shield className="w-5 h-5 text-gray-400" />
        </div>
      )}
      <span className="text-xs font-bold text-white line-clamp-2">{name}</span>
    </button>
  );
}

function EventRow({ event }: { event: FootballMatchEvent }) {
  const minuteLabel = event.extraMinute != null ? `${event.minute}+${event.extraMinute}'` : `${event.minute}'`;
  const type = event.type.toLowerCase();
  const isGoal = type === 'goal';
  const isCard = type === 'card';
  const isRedCard = isCard && event.detail.toLowerCase().includes('red');

  const Icon = isGoal ? Users : isCard ? (isRedCard ? SquareCheckBig : Square) : Square;
  const iconColor = isGoal ? 'text-[#22C55E]' : isRedCard ? 'text-red-500' : isCard ? 'text-amber-500' : 'text-gray-400';

  return (
    <div className="flex items-start gap-3">
      <span className="w-10 text-xs font-black text-gray-400 shrink-0">{minuteLabel}</span>
      <Icon className={`w-4 h-4 mt-0.5 shrink-0 ${iconColor}`} />
      <div className="flex-1 min-w-0">
        <p className="text-sm font-bold text-white">{event.playerName || event.detail}</p>
        <p className="text-xs text-gray-400">
          {[event.detail, event.assistName ? `Assist: ${event.assistName}` : null, event.teamName].filter(Boolean).join(' · ')}
        </p>
      </div>
    </div>
  );
}
