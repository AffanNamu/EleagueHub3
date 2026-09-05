'use client';

import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { useMatchCorrectionAction } from '@/hooks/useMatchCorrectionAction';
import type { KnockoutMatch, LeagueTeamSummary } from '@/types/match';

function teamLabel(teamId: string | null, teams: LeagueTeamSummary[]): string {
  if (!teamId) return 'TBD';
  return teams.find((t) => t.teamId === teamId)?.name ?? teamId;
}

export function KnockoutCorrectionDialog({
  match,
  teams,
  leagueId,
  onClose,
}: {
  match: KnockoutMatch;
  teams: LeagueTeamSummary[];
  leagueId: string;
  onClose: () => void;
}) {
  const { correctKnockout, submitting, error } = useMatchCorrectionAction(leagueId);
  const [homeScore, setHomeScore] = useState(match.homeScore ?? 0);
  const [awayScore, setAwayScore] = useState(match.awayScore ?? 0);
  const [status, setStatus] = useState<'scheduled' | 'completed' | 'played'>(
    match.status === 'completed' || match.status === 'played' ? (match.status as 'completed' | 'played') : 'scheduled',
  );
  const [tiebreakWinner, setTiebreakWinner] = useState(match.tiebreakWinnerTeamId ?? '');

  const isDraw = homeScore === awayScore;

  async function handleSubmit() {
    const ok = await correctKnockout(match.id, {
      homeScore,
      awayScore,
      status,
      tiebreakWinnerTeamId: isDraw && tiebreakWinner ? tiebreakWinner : null,
    });
    if (ok) onClose();
  }

  return (
    <Modal title={`Correct Score — ${match.roundName}`} onClose={onClose}>
      <div className="space-y-4">
        {error && (
          <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
            {error}
          </div>
        )}

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="mb-1 block text-xs text-ink-secondary">{teamLabel(match.homeTeamId, teams)}</label>
            <input
              type="number"
              value={homeScore}
              onChange={(event) => setHomeScore(Number(event.target.value))}
              className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-center text-lg font-semibold text-ink-primary outline-none focus:border-brand"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs text-ink-secondary">{teamLabel(match.awayTeamId, teams)}</label>
            <input
              type="number"
              value={awayScore}
              onChange={(event) => setAwayScore(Number(event.target.value))}
              className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-center text-lg font-semibold text-ink-primary outline-none focus:border-brand"
            />
          </div>
        </div>

        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Status</label>
          <select
            value={status}
            onChange={(event) => setStatus(event.target.value as typeof status)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          >
            <option value="scheduled">Scheduled</option>
            <option value="completed">Completed</option>
            <option value="played">Played</option>
          </select>
        </div>

        {isDraw && (
          <div>
            <label className="mb-1.5 block text-sm text-ink-secondary">
              Winner by Penalties / Tiebreak (drawn on aggregate)
            </label>
            <select
              value={tiebreakWinner}
              onChange={(event) => setTiebreakWinner(event.target.value)}
              className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
            >
              <option value="">Not decided yet</option>
              {match.homeTeamId && <option value={match.homeTeamId}>{teamLabel(match.homeTeamId, teams)}</option>}
              {match.awayTeamId && <option value={match.awayTeamId}>{teamLabel(match.awayTeamId, teams)}</option>}
            </select>
          </div>
        )}

        <div className="flex justify-end gap-2 border-t border-base-border pt-3">
          <button onClick={onClose} className="rounded-sm px-3 py-1.5 text-sm text-ink-secondary hover:bg-base-raised">
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={submitting}
            className="rounded-sm bg-brand px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
          >
            {submitting ? 'Saving…' : 'Save Correction'}
          </button>
        </div>
      </div>
    </Modal>
  );
}
