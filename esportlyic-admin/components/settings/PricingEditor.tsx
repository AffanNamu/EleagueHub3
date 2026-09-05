'use client';

import { useMemo, useState } from 'react';
import { PricingFieldEditor } from '@/components/settings/PricingFieldEditor';
import { usePricingConfigSave } from '@/hooks/usePricingConfigSave';
import type { PricingConfig, PricingFieldValue } from '@/types/pricingConfig';

export function PricingEditor({ config, canEdit }: { config: PricingConfig; canEdit: boolean }) {
  const [values, setValues] = useState<Record<string, PricingFieldValue>>(() =>
    Object.fromEntries(config.fields.map((f) => [f.key, f.value])),
  );
  const { save, submitting, error, saved } = usePricingConfigSave();

  const changedKeys = useMemo(
    () => config.fields.filter((f) => values[f.key] !== f.value).map((f) => f.key),
    [config.fields, values],
  );

  async function handleSave() {
    const updates: Record<string, PricingFieldValue> = {};
    for (const key of changedKeys) {
      const value = values[key];
      if (value !== undefined) updates[key] = value;
    }
    await save(updates);
  }

  return (
    <div className="space-y-4">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}
      {saved && changedKeys.length === 0 && (
        <div className="rounded-sm border border-signal-success/40 bg-signal-successFaint px-3 py-2 text-sm text-signal-success">
          Saved.
        </div>
      )}

      <div className="panel overflow-hidden">
        {config.fields.map((field) => {
          const currentValue = values[field.key];
          return (
            <PricingFieldEditor
              key={field.key}
              field={field}
              value={currentValue !== undefined ? currentValue : field.value}
              disabled={!canEdit}
              onChange={(value) => setValues((prev) => ({ ...prev, [field.key]: value }))}
            />
          );
        })}
      </div>

      {config.unsupportedKeys.length > 0 && (
        <div className="panel p-4">
          <p className="text-xs text-ink-muted">
            Not editable here (non-primitive value): {config.unsupportedKeys.join(', ')}
          </p>
        </div>
      )}

      {canEdit && (
        <button
          onClick={handleSave}
          disabled={submitting || changedKeys.length === 0}
          className="rounded-sm bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
        >
          {submitting ? 'Saving…' : changedKeys.length > 0 ? `Save ${changedKeys.length} Change(s)` : 'No Changes'}
        </button>
      )}
    </div>
  );
}
