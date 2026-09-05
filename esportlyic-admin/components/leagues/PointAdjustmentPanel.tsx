'use client';

import { useState } from 'react';
import { PlusCircle, MinusCircle } from 'lucide-react';
import { usePointAdjustmentAction } from '@/hooks/usePointAdjustmentAction';
import { formatRelativeTime } from '@/lib/utils';
import type { LeagueTeamSummary, PointAdjustment } from '@/types/match';

function teamLabel(teamId: string, teams: LeagueTeamSummary[]): string {
  return teams.find((t) => t.teamId === teamId)?.name ?? teamId;
}

export function PointAdjustmentPanel({
  leagueId,
  teams,
  adjustments,
  canManage,
}: {
  leagueId: string;
  teams: LeagueTeamSummary[];
  adjustments: PointAdjustment[];
  canManage: boolean;
}) {
  const { submit, submitting, error } = usePointAdjustmentAction(leagueId);
  const [teamId, setTeamId] = useState(teams[0]?.teamId ?? '');
  const [type, setType] = useState<'ADDITION' | 'DEDUCTION'>('DEDUCTION');
  const [points, setPoints] = useState(1);
  const [reason, setReason] = useState('');

  async function handleSubmit() {
    const ok = await submit({ teamId, type, points, reason });
    if (ok) setReason('');
  }

  return (
    <div className="space-y-4">
      {canManage && (
        <div className="panel p-5">
          <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">New Point Adjustment</h2>

          {error && (
            <div className="mb-3 rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
              {error}
            </div>
          )}

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
            <select
              value={teamId}
              onChange={(event) => setTeamId(event.target.value)}
              className="rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand sm:col-span-2"
            >
              {teams.map((team) => (
                <option key={team.teamId} value={team.teamId}>
                  {team.name}
                </option>
              ))}
            </select>

            <select
              value={type}
              onChange={(event) => setType(event.target.value as 'ADDITION' | 'DEDUCTION')}
              className="rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
            >
              <option value="DEDUCTION">Deduct</option>
              <option value="ADDITION">Add</option>
            </select>

            <input
              type="number"
              min={1}
              max={1000}
              value={points}
              onChange={(event) => setPoints(Number(event.target.value))}
              className="rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
            />
          </div>

          <textarea
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            placeholder="Reason (required — e.g. 'Unsporting conduct, Match 4')"
            rows={2}
            className="mt-3 w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />

          <button
            onClick={handleSubmit}
            disabled={submitting || !teamId || !reason.trim()}
            className="mt-3 flex items-center gap-2 rounded-sm bg-brand px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
          >
            {type === 'ADDITION' ? <PlusCircle size={15} /> : <MinusCircle size={15} />}
            {submitting ? 'Applying…' : `${type === 'ADDITION' ? 'Add' : 'Deduct'} ${points} Point(s)`}
          </button>
        </div>
      )}

      <div className="panel p-5">
        <h2 className="mb-3 font-display text-sm font-semibold text-ink-primary">Adjustment History</h2>
        {adjustments.length === 0 ? (
          <p className="text-sm text-ink-secondary">No manual adjustments on this league yet.</p>
        ) : (
          <div className="space-y-2">
            {adjustments.map((adj) => (
              <div key={adj.id} className="rounded-sm bg-base-raised p-3 text-sm">
                <p className="text-ink-primary">
                  {adj.type === 'ADDITION' ? '+' : '−'}
                  {adj.points} — {teamLabel(adj.teamId, teams)}
                </p>
                <p className="mt-0.5 text-xs text-ink-secondary">{adj.reason}</p>
                <p className="mt-1 text-xs text-ink-muted">{formatRelativeTime(adj.createdAtMs)}</p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
