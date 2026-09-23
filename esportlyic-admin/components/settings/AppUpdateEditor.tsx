'use client';

import { useMemo, useState } from 'react';
import { useAppUpdateConfigSave } from '@/hooks/useAppUpdateConfigSave';
import type { AppUpdateConfig, AppUpdateConfigEdit } from '@/types/appUpdateConfig';

function fieldLabel(label: string, fieldKey: string) {
  return (
    <div className="min-w-0">
      <p className="text-sm text-ink-primary">{label}</p>
      <p className="font-mono text-xs text-ink-muted">{fieldKey}</p>
    </div>
  );
}

export function AppUpdateEditor({ config, canEdit }: { config: AppUpdateConfig; canEdit: boolean }) {
  const [form, setForm] = useState<AppUpdateConfig>(config);
  const { save, submitting, error, saved } = useAppUpdateConfigSave();

  const edit = useMemo<AppUpdateConfigEdit>(() => {
    const out: AppUpdateConfigEdit = {};
    for (const key of Object.keys(config) as (keyof AppUpdateConfig)[]) {
      if (form[key] !== config[key]) (out as Record<string, unknown>)[key] = form[key];
    }
    return out;
  }, [config, form]);

  const dirty = Object.keys(edit).length > 0;

  function set<K extends keyof AppUpdateConfig>(key: K, value: AppUpdateConfig[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  async function handleSave() {
    await save(edit);
  }

  return (
    <div className="space-y-4">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}
      {saved && !dirty && (
        <div className="rounded-sm border border-signal-success/40 bg-signal-successFaint px-3 py-2 text-sm text-signal-success">
          Saved.
        </div>
      )}

      <div className="panel overflow-hidden">
        <div className="grid grid-cols-[1fr_16rem] items-center gap-3 border-b border-base-border bg-base-raised/50 px-4 py-2.5 last:border-0">
          {fieldLabel('Latest version name', 'latestVersionName')}
          <input
            type="text"
            placeholder="e.g. 1.9.13"
            value={form.latestVersionName}
            disabled={!canEdit}
            onChange={(e) => set('latestVersionName', e.target.value)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-2.5 py-1.5 text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
          />
        </div>

        <div className="grid grid-cols-[1fr_16rem] items-center gap-3 border-b border-base-border px-4 py-2.5 last:border-0">
          {fieldLabel('Latest build number', 'latestBuildNumber')}
          <input
            type="number"
            min={0}
            step="1"
            value={form.latestBuildNumber}
            disabled={!canEdit}
            onChange={(e) => set('latestBuildNumber', Math.max(0, Math.trunc(Number(e.target.value) || 0)))}
            className="w-full rounded-sm border border-base-border bg-base-raised px-2.5 py-1.5 text-right text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
          />
        </div>

        <div className="grid grid-cols-[1fr_16rem] items-center gap-3 border-b border-base-border px-4 py-2.5 last:border-0">
          {fieldLabel('Play Store URL', 'playStoreUrl')}
          <input
            type="text"
            placeholder="https://play.google.com/store/apps/details?id=..."
            value={form.playStoreUrl}
            disabled={!canEdit}
            onChange={(e) => set('playStoreUrl', e.target.value)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-2.5 py-1.5 text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
          />
        </div>

        <div className="grid grid-cols-[1fr_16rem] items-center gap-3 border-b border-base-border px-4 py-2.5 last:border-0">
          {fieldLabel('App Store URL', 'appStoreUrl')}
          <input
            type="text"
            placeholder="https://apps.apple.com/app/id..."
            value={form.appStoreUrl}
            disabled={!canEdit}
            onChange={(e) => set('appStoreUrl', e.target.value)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-2.5 py-1.5 text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
          />
        </div>

        <div className="grid grid-cols-[1fr_16rem] items-start gap-3 px-4 py-2.5">
          {fieldLabel('Release notes', 'releaseNotes')}
          <textarea
            rows={3}
            placeholder="Shown to users alongside the update prompt."
            value={form.releaseNotes}
            disabled={!canEdit}
            onChange={(e) => set('releaseNotes', e.target.value)}
            className="w-full resize-y rounded-sm border border-base-border bg-base-raised px-2.5 py-1.5 text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
          />
        </div>
      </div>

      <div
        className={`panel flex items-start gap-3 p-4 ${
          form.forceUpdate ? 'border-signal-danger/40 bg-signal-dangerFaint' : ''
        }`}
      >
        <input
          type="checkbox"
          id="forceUpdate"
          checked={form.forceUpdate}
          disabled={!canEdit}
          onChange={(e) => set('forceUpdate', e.target.checked)}
          className="mt-0.5 h-4 w-4 rounded-sm border-base-border bg-base-raised text-signal-danger focus:ring-signal-danger disabled:opacity-60"
        />
        <label htmlFor="forceUpdate" className="min-w-0">
          <p className={`text-sm font-medium ${form.forceUpdate ? 'text-signal-danger' : 'text-ink-primary'}`}>
            Force this update
          </p>
          <p className="mt-0.5 text-xs text-ink-secondary">
            When on, every install behind the build number above is redirected to a full-screen
            &quot;Update Required&quot; wall and can&apos;t use the app at all until they update — no
            &quot;Later&quot; option. When off, users see a dismissible &quot;Update Available&quot;
            prompt they can skip.
          </p>
        </label>
      </div>

      {canEdit && (
        <button
          onClick={handleSave}
          disabled={submitting || !dirty}
          className="rounded-sm bg-brand px-4 py-2 text-sm font-medium text-base hover:bg-brand-soft disabled:opacity-60"
        >
          {submitting ? 'Saving…' : dirty ? 'Save Changes' : 'No Changes'}
        </button>
      )}
    </div>
  );
}
