'use client';

import { useState } from 'react';
import { useLeagueSave } from '@/hooks/useLeagueActions';
import type { League, LeagueInput } from '@/types/league';

const inputClass =
  'w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand';
const labelClass = 'mb-1.5 block text-sm text-ink-secondary';

export function LeagueEditForm({ league }: { league: League }) {
  const { save, submitting, error } = useLeagueSave(league.id);

  const [name, setName] = useState(league.name);
  const [description, setDescription] = useState(league.description);
  const [isPrivate, setIsPrivate] = useState(league.isPrivate);
  const [region, setRegion] = useState(league.region);
  const [season, setSeason] = useState(league.season);
  const [leagueImageUrl, setLeagueImageUrl] = useState(league.leagueImageUrl);
  const [sponsorImageUrl, setSponsorImageUrl] = useState(league.sponsorImageUrl);

  async function handleSubmit() {
    const input: LeagueInput = {
      name,
      description,
      isPrivate,
      region,
      season,
      leagueImageUrl,
      sponsorImageUrl,
    };
    await save(input);
  }

  return (
    <div className="panel space-y-4 p-5">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div className="rounded-sm border border-signal-warning/40 bg-signal-warningFaint px-3 py-2 text-xs text-signal-warning">
        Format, max teams, and ownership can't be edited here — changing them on a league that
        already has matches/teams/a bracket would break the existing data.
      </div>

      <div>
        <label className={labelClass}>Name</label>
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={100} className={inputClass} />
      </div>

      <div>
        <label className={labelClass}>Description</label>
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          maxLength={2000}
          rows={3}
          className={inputClass}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className={labelClass}>Region</label>
          <input value={region} onChange={(e) => setRegion(e.target.value)} className={inputClass} />
        </div>
        <div>
          <label className={labelClass}>Season</label>
          <input value={season} onChange={(e) => setSeason(e.target.value)} className={inputClass} />
        </div>
      </div>

      <div>
        <label className={labelClass}>League image URL</label>
        <input
          value={leagueImageUrl}
          onChange={(e) => setLeagueImageUrl(e.target.value)}
          className={inputClass}
        />
      </div>

      <div>
        <label className={labelClass}>Sponsor image URL</label>
        <input
          value={sponsorImageUrl}
          onChange={(e) => setSponsorImageUrl(e.target.value)}
          className={inputClass}
        />
      </div>

      <label className="flex items-center gap-2 text-sm text-ink-secondary">
        <input
          type="checkbox"
          checked={isPrivate}
          onChange={(e) => setIsPrivate(e.target.checked)}
          className="h-4 w-4 rounded-sm border-base-border accent-brand"
        />
        Private (invite-only, hidden from public discovery)
      </label>

      <div className="flex justify-end pt-2">
        <button
          onClick={handleSubmit}
          disabled={submitting || !name.trim()}
          className="rounded-sm bg-brand px-4 py-2 text-sm font-medium text-base hover:bg-brand-soft disabled:opacity-60"
        >
          {submitting ? 'Saving…' : 'Save changes'}
        </button>
      </div>
    </div>
  );
}
