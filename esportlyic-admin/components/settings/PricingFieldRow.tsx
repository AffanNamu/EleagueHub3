'use client';

export function PricingFieldRow({
  label,
  fieldKey,
  type,
  ngnValue,
  usdValue,
  onChangeNgn,
  onChangeUsd,
  disabled,
}: {
  label: string;
  fieldKey: string;
  type: 'number' | 'boolean' | 'nullableNumber';
  ngnValue: number | boolean | null;
  usdValue: number | boolean | null;
  onChangeNgn: (value: number | boolean | null) => void;
  onChangeUsd: (value: number | boolean | null) => void;
  disabled: boolean;
}) {
  return (
    <div className="grid grid-cols-[1fr_9rem_9rem] items-center gap-3 border-b border-base-border px-4 py-2.5 last:border-0">
      <div className="min-w-0">
        <p className="text-sm text-ink-primary">{label}</p>
        <p className="font-mono text-xs text-ink-muted">{fieldKey}</p>
      </div>
      <CurrencyCell type={type} value={ngnValue} onChange={onChangeNgn} disabled={disabled} prefix="₦" />
      <CurrencyCell type={type} value={usdValue} onChange={onChangeUsd} disabled={disabled} prefix="$" />
    </div>
  );
}

function CurrencyCell({
  type,
  value,
  onChange,
  disabled,
  prefix,
}: {
  type: 'number' | 'boolean' | 'nullableNumber';
  value: number | boolean | null;
  onChange: (value: number | boolean | null) => void;
  disabled: boolean;
  prefix: string;
}) {
  if (type === 'boolean') {
    return (
      <label className="flex items-center justify-center gap-2">
        <input
          type="checkbox"
          checked={value === true}
          disabled={disabled}
          onChange={(e) => onChange(e.target.checked)}
          className="h-4 w-4 rounded-sm border-base-border bg-base-raised text-brand focus:ring-brand disabled:opacity-60"
        />
      </label>
    );
  }

  const isEmpty = value === null || value === undefined;

  return (
    <div className="relative">
      <span className="pointer-events-none absolute left-2 top-1/2 -translate-y-1/2 text-xs text-ink-muted">
        {prefix}
      </span>
      <input
        type="number"
        min={0}
        step="0.01"
        placeholder={type === 'nullableNumber' ? 'None' : undefined}
        value={isEmpty ? '' : (value as number)}
        disabled={disabled}
        onChange={(e) => {
          const raw = e.target.value;
          if (raw === '') {
            onChange(type === 'nullableNumber' ? null : 0);
            return;
          }
          const n = Number(raw);
          onChange(Number.isFinite(n) ? n : 0);
        }}
        className="w-full rounded-sm border border-base-border bg-base-raised py-1 pl-5 pr-2.5 text-right text-sm text-ink-primary outline-none focus:border-brand disabled:opacity-60"
      />
    </div>
  );
}
