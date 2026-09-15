'use client';

import { useState } from 'react';
import { useOrganizerSave } from '@/hooks/useOrganizerActions';
import type { MasterLeaguePlanId, Organizer, OrganizerInput, OrganizerSocialLinks } from '@/types/organizer';

const inputClass =
  'w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand';
const labelClass = 'mb-1.5 block text-sm text-ink-secondary';

const SOCIAL_FIELDS: Array<{ key: keyof OrganizerSocialLinks; label: string }> = [
  { key: 'website', label: 'Website' },
  { key: 'facebook', label: 'Facebook' },
  { key: 'instagram', label: 'Instagram' },
  { key: 'x', label: 'X (Twitter)' },
  { key: 'twitter', label: 'Twitter (legacy)' },
  { key: 'discord', label: 'Discord' },
  { key: 'youtube', label: 'YouTube' },
  { key: 'twitch', label: 'Twitch' },
  { key: 'tiktok', label: 'TikTok' },
];

const PLANS: MasterLeaguePlanId[] = ['basic', 'pro', 'elite'];

export function OrganizerEditForm({ organizer }: { organizer: Organizer }) {
  const { save, submitting, error } = useOrganizerSave(organizer.id);

  const [name, setName] = useState(organizer.name);
  const [plan, setPlan] = useState<MasterLeaguePlanId>(organizer.plan);
  const [bio, setBio] = useState(organizer.bio);
  const [logoUrl, setLogoUrl] = useState(organizer.logoUrl);
  const [bannerUrl, setBannerUrl] = useState(organizer.bannerUrl);
  const [country, setCountry] = useState(organizer.country);
  const [socialLinks, setSocialLinks] = useState<OrganizerSocialLinks>(organizer.socialLinks);

  function updateSocial(key: keyof OrganizerSocialLinks, value: string) {
    setSocialLinks((prev) => ({ ...prev, [key]: value }));
  }

  async function handleSubmit() {
    const input: OrganizerInput = {
      name,
      plan,
      bio,
      logoUrl,
      bannerUrl,
      country,
      socialLinks,
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
        Ownership, membership, staff roles, verification, and analytics can't be edited here.
        Changing the plan here changes what the workspace can actually do (competition/team
        limits, features) — it bypasses the normal payment/entitlement flow, so use it carefully.
      </div>

      <div>
        <label className={labelClass}>Name</label>
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={100} className={inputClass} />
      </div>

      <div>
        <label className={labelClass}>Plan</label>
        <select
          value={plan}
          onChange={(e) => setPlan(e.target.value as MasterLeaguePlanId)}
          className={inputClass}
        >
          {PLANS.map((p) => (
            <option key={p} value={p}>
              {p.charAt(0).toUpperCase() + p.slice(1)}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label className={labelClass}>Bio</label>
        <textarea value={bio} onChange={(e) => setBio(e.target.value)} maxLength={2000} rows={3} className={inputClass} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className={labelClass}>Logo URL</label>
          <input value={logoUrl} onChange={(e) => setLogoUrl(e.target.value)} className={inputClass} />
        </div>
        <div>
          <label className={labelClass}>Banner URL</label>
          <input value={bannerUrl} onChange={(e) => setBannerUrl(e.target.value)} className={inputClass} />
        </div>
      </div>

      <div>
        <label className={labelClass}>Country</label>
        <input value={country} onChange={(e) => setCountry(e.target.value)} className={inputClass} />
      </div>

      <div>
        <h3 className="mb-2 text-sm font-medium text-ink-primary">Social links</h3>
        <div className="grid grid-cols-2 gap-3">
          {SOCIAL_FIELDS.map(({ key, label }) => (
            <div key={key}>
              <label className={labelClass}>{label}</label>
              <input
                value={socialLinks[key] ?? ''}
                onChange={(e) => updateSocial(key, e.target.value)}
                className={inputClass}
              />
            </div>
          ))}
        </div>
      </div>

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
