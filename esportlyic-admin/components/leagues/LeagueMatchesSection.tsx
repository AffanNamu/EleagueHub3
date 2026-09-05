'use client';

import { useState } from 'react';
import { cn } from '@/lib/utils';
import { MatchesTable } from '@/components/leagues/MatchesTable';
import { KnockoutMatchesTable } from '@/components/leagues/KnockoutMatchesTable';
import { PointAdjustmentPanel } from '@/components/leagues/PointAdjustmentPanel';
import type { FixtureMatch, KnockoutMatch, LeagueTeamSummary, PointAdjustment } from '@/types/match';

type Tab = 'fixtures' | 'knockout' | 'adjustments';

export function LeagueMatchesSection({
  leagueId,
  fixtures,
  knockout,
  teams,
  adjustments,
  canManage,
}: {
  leagueId: string;
  fixtures: FixtureMatch[];
  knockout: KnockoutMatch[];
  teams: LeagueTeamSummary[];
  adjustments: PointAdjustment[];
  canManage: boolean;
}) {
  const [tab, setTab] = useState<Tab>(fixtures.length > 0 ? 'fixtures' : knockout.length > 0 ? 'knockout' : 'fixtures');

  const tabs: { id: Tab; label: string }[] = [
    { id: 'fixtures', label: `Fixtures (${fixtures.length})` },
    { id: 'knockout', label: `Knockout (${knockout.length})` },
    { id: 'adjustments', label: `Point Adjustments (${adjustments.length})` },
  ];

  return (
    <div className="space-y-3">
      <div className="flex gap-1 border-b border-base-border">
        {tabs.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={cn(
              'border-b-2 px-3 py-2 text-sm transition-colors',
              tab === t.id ? 'border-brand text-brand' : 'border-transparent text-ink-secondary hover:text-ink-primary',
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'fixtures' && <MatchesTable matches={fixtures} teams={teams} leagueId={leagueId} canManage={canManage} />}
      {tab === 'knockout' && <KnockoutMatchesTable matches={knockout} teams={teams} leagueId={leagueId} canManage={canManage} />}
      {tab === 'adjustments' && (
        <PointAdjustmentPanel leagueId={leagueId} teams={teams} adjustments={adjustments} canManage={canManage} />
      )}
    </div>
  );
}
