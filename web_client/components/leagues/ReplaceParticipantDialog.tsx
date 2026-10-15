'use client';

// Safe participant replacement, web side. A two-step modal (pick a
// replacement -> preview -> confirm/cancel) over
// previewReplaceParticipant/commitReplaceParticipant
// (lib/leagues/replaceParticipantRepository.ts). Works for every format,
// unlike the Late Join dialog, since the replacement slots into an
// EXISTING fixture position rather than requiring a new one.

import { useEffect, useState } from 'react';
import { X, Repeat, Loader2 } from 'lucide-react';
import { Team } from '@/lib/models/leagueDetails';
import {
  getEligibleReplacementTeams,
  previewReplaceParticipant,
  commitReplaceParticipant,
  createReplacementTeam,
} from '@/lib/leagues/replaceParticipantRepository';
import { ReplaceParticipantPreview } from '@/lib/algorithms/replaceParticipantPlanner';
import { auth } from '@/lib/firebase';

export function ReplaceParticipantDialog({
  leagueId,
  oldTeam,
  onDone,
  onCancel,
}: {
  leagueId: string;
  oldTeam: Team;
  onDone: (result: { newTeamName: string; matchesUpdated: number }) => void;
  onCancel: () => void;
}) {
  const [eligible, setEligible] = useState<Team[] | null>(null);
  const [useNewTeam, setUseNewTeam] = useState(false);
  const [selectedId, setSelectedId] = useState('');
  const [newName, setNewName] = useState('');
  const [preview, setPreview] = useState<ReplaceParticipantPreview | null>(null);
  const [resolvedTeam, setResolvedTeam] = useState<Team | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      try {
        const list = await getEligibleReplacementTeams({ leagueId, excludeTeamId: oldTeam.id });
        setEligible(list);
        if (list.length > 0) {
          setSelectedId(list[0].id);
        } else {
          setUseNewTeam(true);
        }
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
        setEligible([]);
      }
    })();
  }, [leagueId, oldTeam.id]);

  const doPreview = async () => {
    setBusy(true);
    setError('');
    try {
      let team: Team;
      if (useNewTeam) {
        if (!newName.trim()) {
          setError('Please enter a team name.');
          setBusy(false);
          return;
        }
        team = await createReplacementTeam({ leagueId, name: newName });
      } else {
        const found = (eligible ?? []).find((t) => t.id === selectedId);
        if (!found) {
          setError('Please choose a replacement team.');
          setBusy(false);
          return;
        }
        team = found;
      }
      const result = await previewReplaceParticipant({ leagueId, oldTeamId: oldTeam.id, newTeamId: team.id });
      setResolvedTeam(team);
      setPreview(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  const doConfirm = async () => {
    if (!resolvedTeam) return;
    setBusy(true);
    setError('');
    try {
      const performedBy = auth.currentUser?.uid ?? '';
      const result = await commitReplaceParticipant({
        leagueId,
        oldTeamId: oldTeam.id,
        newTeamId: resolvedTeam.id,
        performedBy,
      });
      onDone({
        newTeamName: resolvedTeam.name,
        matchesUpdated: result.fixtureMatchesToUpdate.length + result.knockoutMatchesToUpdate.length,
      });
    } catch (e) {
      setBusy(false);
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 shadow-xl">
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-lg font-black text-white flex items-center gap-2">
            <Repeat className="w-5 h-5 text-[#BEF264]" />
            Replace &quot;{oldTeam.name}&quot;
          </h2>
          <button onClick={onCancel} className="p-1 text-gray-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>
        <p className="text-xs text-gray-400 mb-4">
          Completed matches are never changed. Only this team&apos;s upcoming, not-yet-played matches will be
          reassigned.
        </p>

        {!preview ? (
          eligible === null ? (
            <div className="flex justify-center py-6">
              <Loader2 className="w-6 h-6 text-[#BEF264] animate-spin" />
            </div>
          ) : (
            <>
              {eligible.length > 0 && (
                <div className="flex gap-4 mb-3 text-sm text-gray-300">
                  <label className="flex items-center gap-2">
                    <input type="radio" checked={!useNewTeam} onChange={() => setUseNewTeam(false)} />
                    Existing team
                  </label>
                  <label className="flex items-center gap-2">
                    <input type="radio" checked={useNewTeam} onChange={() => setUseNewTeam(true)} />
                    New team
                  </label>
                </div>
              )}
              {!useNewTeam && eligible.length > 0 ? (
                <select
                  value={selectedId}
                  onChange={(e) => setSelectedId(e.target.value)}
                  disabled={busy}
                  className="w-full bg-[#111827] border border-white/10 rounded-lg p-3 text-white focus:border-[#BEF264]"
                >
                  {eligible.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.name}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  type="text"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  disabled={busy}
                  placeholder="New team name"
                  className="w-full bg-[#111827] border border-white/10 rounded-lg p-3 text-white focus:border-[#BEF264]"
                />
              )}
            </>
          )
        ) : (
          <div className="bg-[#111827] rounded-xl p-4 mb-2 space-y-2 text-sm">
            <Row label="Completed matches (untouched)" value={preview.completedMatchCount} />
            <Row label="Fixtures to be reassigned" value={preview.fixtureMatchesToUpdate.length} />
            <Row label="Knockout matches to be reassigned" value={preview.knockoutMatchesToUpdate.length} />
            <Row label="Completed matches affected" value={preview.completedMatchesAffectedCount} />
          </div>
        )}

        {error && <p className="text-xs text-red-400 mt-2">{error}</p>}

        <div className="flex justify-end gap-2 mt-4">
          <button
            onClick={onCancel}
            disabled={busy}
            className="px-4 py-2 text-sm font-bold text-gray-300 hover:text-white disabled:opacity-40"
          >
            Cancel
          </button>
          <button
            onClick={preview ? doConfirm : doPreview}
            disabled={busy || eligible === null}
            className="px-4 py-2 bg-[#BEF264] text-brand-navy font-black rounded-lg hover:bg-[#BEF264]/90 disabled:opacity-50 flex items-center gap-2 text-sm"
          >
            {busy && <Loader2 className="w-4 h-4 animate-spin" />}
            {preview ? 'Confirm Replacement' : 'Preview'}
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
