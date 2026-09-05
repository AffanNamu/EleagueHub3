'use client';

import type { PricingConfigField, PricingFieldValue } from '@/types/pricingConfig';

function humanizeKey(key: string): string {
  return key
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/^./, (c) => c.toUpperCase());
}

export function PricingFieldEditor({
  field,
  value,
  onChange,
  disabled,
}: {
  field: PricingConfigField;
  value: PricingFieldValue;
  onChange: (value: PricingFieldValue) => void;
  disabled: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-base-border px-4 py-2.5 last:border-0">
      <div className="min-w-0">
        <p className="text-sm text-ink-primary">{humanizeKey(field.key)}</p>
        <p className="font-mono text-xs text-ink-muted">{field.key}</p>
      </div>

      {field.type === 'boolean' ? (
        <label className="flex flex-shrink-0 items-center gap-2">
          <input
            type="checkbox"
            checked={value === true}
            disabled={disabled}
            onChange={(event) => onChange(event.target.checked)}
            className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand disabled:opacity-60"
          />
        </label>
      ) : field.type === 'number' ? (
        <input
          type="number"
          value={value as number}
          disabled={disabled}
          onChange={(event) => onChange(Number(event.target.value))}
          className="w-32 flex-shrink-0 rounded-sm border border-base-border bg-base-raised px-2.5 py-1 text-right text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
        />
      ) : (
        <input
          type="text"
          value={value as string}
          disabled={disabled}
          onChange={(event) => onChange(event.target.value)}
          className="w-48 flex-shrink-0 rounded-sm border border-base-border bg-base-raised px-2.5 py-1 text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
        />
      )}
    </div>
  );
}
