'use client';

// PHASE D: safe late-participant join for Classic League, web side. A
// two-step modal (name -> preview -> confirm/cancel) over
// previewLateJoin/commitLateJoin (lib/leagues/lateJoinRepository.ts) --
// mirrors add_teams_screen.dart's _openLateJoinDialog. Never touches an
// existing match: previewLateJoin only reads; commitLateJoin only adds a
// new team doc and new fixture docs.

import { useState } from 'react';
import { X, UserPlus, Loader2 } from 'lucide-react';
import { LeagueFormat } from '@/lib/models/leagueFormat';
import { previewLateJoin, commitLateJoin } from '@/lib/leagues/lateJoinRepository';
import { LateJoinPreview } from '@/lib/algorithms/lateJoinPlanner';

export function LateJoinDialog({
  leagueId,
  format,
  doubleRoundRobin,
  onDone,
  onCancel,
}: {
  leagueId: string;
  format: LeagueFormat;
  doubleRoundRobin: boolean;
  onDone: (result: { teamName: string; newFixtureCount: number }) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState('');
  const [preview, setPreview] = useState<LateJoinPreview | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const doPreview = async () => {
    if (!name.trim()) {
      setError('Please enter a team name.');
      return;
    }
    setLoading(true);
    setError('');
    try {
      const result = await previewLateJoin({ leagueId, format, doubleRoundRobin });
      setPreview(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  };

  const doConfirm = async () => {
    setLoading(true);
    setError('');
    try {
      const result = await commitLateJoin({ leagueId, format, doubleRoundRobin, newTeamName: name });
      onDone({ teamName: result.team.name, newFixtureCount: result.preview.newFixtures.length });
    } catch (e) {
      setLoading(false);
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-lg font-black text-white flex items-center gap-2">
            <UserPlus className="w-5 h-5 text-[#BEF264]" />
            Add a Late-Joining Team
          </h2>
          <button onClick={onCancel} className="p-1 text-gray-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>
        <p className="text-xs text-gray-400 mb-4">
          This never changes an existing match. It only creates new fixtures between the new team and every
          current team.
        </p>

        {!preview ? (
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            disabled={loading}
            placeholder="Team name"
            className="w-full bg-[#111827] border border-white/10 rounded-lg p-3 text-white focus:border-[#BEF264] mb-2"
          />
        ) : (
          <div className="bg-[#111827] rounded-xl p-4 mb-2 space-y-2 text-sm">
            <Row label="Completed matches (untouched)" value={preview.completedMatchCount} />
            <Row label="Future matches (untouched)" value={preview.futureMatchCount} />
            <Row label="New fixtures to be created" value={preview.newFixtures.length} />
            <Row label="Existing matches affected" value={preview.existingMatchesAffectedCount} />
          </div>
        )}

        {error && <p className="text-xs text-red-400 mb-2">{error}</p>}

        <div className="flex justify-end gap-2 mt-4">
          <button
            onClick={onCancel}
            disabled={loading}
            className="px-4 py-2 text-sm font-bold text-gray-300 hover:text-white disabled:opacity-40"
          >
            Cancel
          </button>
          <button
            onClick={preview ? doConfirm : doPreview}
            disabled={loading}
            className="px-4 py-2 bg-[#BEF264] text-brand-navy font-black rounded-lg hover:bg-[#BEF264]/90 disabled:opacity-50 flex items-center gap-2 text-sm"
          >
            {loading && <Loader2 className="w-4 h-4 animate-spin" />}
            {preview ? 'Confirm & Add' : 'Preview'}
          </button>
        </div>
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex justify-between">
      <span className="text-gray-400">{label}</span>
      <span className="text-white font-bold">{value}</span>
    </div>
  );
}
