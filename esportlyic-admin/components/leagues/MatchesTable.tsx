'use client';

import { useState } from 'react';
import { Pencil } from 'lucide-react';
import { Badge } from '@/components/ui/Badge';
import { EmptyState } from '@/components/ui/EmptyState';
import { MatchCorrectionDialog } from '@/components/leagues/MatchCorrectionDialog';
import { matchStatusLabel, matchStatusTone } from '@/lib/models/match';
import { Trophy } from 'lucide-react';
import type { FixtureMatch, LeagueTeamSummary } from '@/types/match';

function teamLabel(teamId: string, teams: LeagueTeamSummary[]): string {
  return teams.find((t) => t.teamId === teamId)?.name ?? teamId;
}

export function MatchesTable({
  matches,
  teams,
  leagueId,
  canManage,
}: {
  matches: FixtureMatch[];
  teams: LeagueTeamSummary[];
  leagueId: string;
  canManage: boolean;
}) {
  const [editingMatch, setEditingMatch] = useState<FixtureMatch | null>(null);

  if (matches.length === 0) {
    return <EmptyState icon={Trophy} title="No matches yet" />;
  }

  return (
    <div className="panel overflow-hidden">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-base-border text-left text-xs text-ink-muted">
            <th className="px-4 py-3 font-medium">Round</th>
            <th className="px-4 py-3 font-medium">Match</th>
            <th className="px-4 py-3 font-medium">Score</th>
            <th className="px-4 py-3 font-medium">Status</th>
            {canManage && <th className="px-4 py-3 font-medium" />}
          </tr>
        </thead>
        <tbody>
          {matches.map((match) => (
            <tr key={match.id} className="border-b border-base-border last:border-0 hover:bg-base-raised">
              <td className="px-4 py-3 text-ink-secondary">{match.roundNumber}</td>
              <td className="px-4 py-3 text-ink-primary">
                {teamLabel(match.homeTeamId, teams)} vs {teamLabel(match.awayTeamId, teams)}
              </td>
              <td className="px-4 py-3 text-ink-primary">
                {match.homeScore ?? '—'} – {match.awayScore ?? '—'}
              </td>
              <td className="px-4 py-3">
                <Badge tone={matchStatusTone(match.status)}>{matchStatusLabel(match.status)}</Badge>
              </td>
              {canManage && (
                <td className="px-4 py-3">
                  <button
                    onClick={() => setEditingMatch(match)}
                    className="rounded-sm p-1.5 text-ink-secondary hover:bg-base-raised hover:text-brand"
                    aria-label="Correct score"
                  >
                    <Pencil size={14} />
                  </button>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>

      {editingMatch && (
        <MatchCorrectionDialog
          match={editingMatch}
          teams={teams}
          leagueId={leagueId}
          onClose={() => setEditingMatch(null)}
        />
      )}
    </div>
  );
}
