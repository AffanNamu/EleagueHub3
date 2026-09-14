'use client';

import { useMemo, useState } from 'react';
import { PricingFieldRow } from '@/components/settings/PricingFieldRow';
import { usePricingConfigSave } from '@/hooks/usePricingConfigSave';
import type { CurrencyPricing, PricingConfig, PricingFieldEdit } from '@/types/pricingConfig';

type FieldType = 'number' | 'boolean' | 'nullableNumber';

interface FieldSpec {
  key: keyof CurrencyPricing;
  label: string;
  type: FieldType;
}

const PLAN_FEE_FIELDS: FieldSpec[] = [
  { key: 'proPlan1moFee', label: 'Pro — Monthly', type: 'number' },
  { key: 'proPlan3moFee', label: 'Pro — 3 Months', type: 'number' },
  { key: 'proPlan6moFee', label: 'Pro — 6 Months', type: 'number' },
  { key: 'proPlanYearlyFee', label: 'Pro — Yearly', type: 'number' },
  { key: 'elitePlan1moFee', label: 'Elite — Monthly', type: 'number' },
  { key: 'elitePlan3moFee', label: 'Elite — 3 Months', type: 'number' },
  { key: 'elitePlan6moFee', label: 'Elite — 6 Months', type: 'number' },
  { key: 'elitePlanYearlyFee', label: 'Elite — Yearly', type: 'number' },
];

const VERIFICATION_FIELDS: FieldSpec[] = [
  { key: 'organizerVerificationFee', label: 'Verification fee', type: 'number' },
  { key: 'organizerVerificationEnabled', label: 'Verification enabled', type: 'boolean' },
  { key: 'organizerVerificationRenewalFee', label: 'Renewal fee', type: 'number' },
  { key: 'organizerVerificationRenewalEnabled', label: 'Renewal enabled', type: 'boolean' },
  { key: 'organizerVerificationDurationDays', label: 'Validity (days)', type: 'number' },
];

const LEAGUE_FIELDS: FieldSpec[] = [
  { key: 'createLeagueFee', label: 'Create league fee', type: 'number' },
  { key: 'accessFee', label: 'League access fee', type: 'number' },
  { key: 'couponUnit', label: 'Coupon unit', type: 'number' },
  { key: 'couponThreshold', label: 'Coupon threshold', type: 'nullableNumber' },
  { key: 'couponDiscountPercent', label: 'Coupon discount (%)', type: 'number' },
  { key: 'premiumFee', label: 'Legacy premium fee', type: 'number' },
  { key: 'premiumDurationDays', label: 'Legacy premium duration (days)', type: 'number' },
  { key: 'premiumEnabled', label: 'Legacy premium enabled', type: 'boolean' },
  { key: 'masterLeagueBasicFee', label: 'Master League — Basic (legacy)', type: 'number' },
  { key: 'masterLeagueProFee', label: 'Master League — Pro (legacy)', type: 'number' },
  { key: 'masterLeagueEliteFee', label: 'Master League — Elite (legacy)', type: 'number' },
];

const TOGGLE_FIELDS: FieldSpec[] = [
  { key: 'paymentsEnabled', label: 'Payments enabled', type: 'boolean' },
  { key: 'flutterwaveEnabled', label: 'Flutterwave enabled', type: 'boolean' },
];

export function PricingEditor({ config, canEdit }: { config: PricingConfig; canEdit: boolean }) {
  const [ngn, setNgn] = useState<CurrencyPricing>(config.ngn);
  const [usd, setUsd] = useState<CurrencyPricing>(config.usd);
  const { save, submitting, error, saved } = usePricingConfigSave();

  const edits = useMemo<PricingFieldEdit[]>(() => {
    const out: PricingFieldEdit[] = [];
    for (const key of Object.keys(config.ngn) as (keyof CurrencyPricing)[]) {
      if (ngn[key] !== config.ngn[key]) out.push({ currency: 'ngn', key, value: ngn[key] });
      if (usd[key] !== config.usd[key]) out.push({ currency: 'usd', key, value: usd[key] });
    }
    return out;
  }, [config, ngn, usd]);

  function setNgnField(key: keyof CurrencyPricing, value: number | boolean | null) {
    setNgn((prev) => ({ ...prev, [key]: value }));
  }
  function setUsdField(key: keyof CurrencyPricing, value: number | boolean | null) {
    setUsd((prev) => ({ ...prev, [key]: value }));
  }

  async function handleSave() {
    const ok = await save(edits);
    // On success the server round-trips fresh data via router.refresh();
    // local state stays as-is (already matches what was just saved).
    void ok;
  }

  function renderSection(title: string, fields: FieldSpec[]) {
    return (
      <div className="panel overflow-hidden">
        <div className="grid grid-cols-[1fr_9rem_9rem] items-center gap-3 border-b border-base-border bg-base-raised/50 px-4 py-2 text-xs font-medium uppercase tracking-wide text-ink-muted">
          <span>{title}</span>
          <span className="text-center">NGN (₦)</span>
          <span className="text-center">USD ($)</span>
        </div>
        {fields.map((f) => (
          <PricingFieldRow
            key={f.key}
            fieldKey={f.key}
            label={f.label}
            type={f.type}
            ngnValue={ngn[f.key]}
            usdValue={usd[f.key]}
            onChangeNgn={(v) => setNgnField(f.key, v)}
            onChangeUsd={(v) => setUsdField(f.key, v)}
            disabled={!canEdit}
          />
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {config.sourceDoc !== 'app_config/pricing' && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {config.sourceDoc === 'defaults'
            ? 'No pricing document exists yet — showing built-in defaults. Saving will create app_config/pricing.'
            : 'Reading from the legacy fallback doc (app/pricing) — app_config/pricing doesn\'t exist yet. Saving will create it as the new primary doc.'}
        </div>
      )}
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}
      {saved && edits.length === 0 && (
        <div className="rounded-sm border border-signal-success/40 bg-signal-successFaint px-3 py-2 text-sm text-signal-success">
          Saved.
        </div>
      )}

      {renderSection('Master League Plan Fees', PLAN_FEE_FIELDS)}
      {renderSection('Organizer Verification', VERIFICATION_FIELDS)}
      {renderSection('League & Access Fees', LEAGUE_FIELDS)}
      {renderSection('Payment Toggles', TOGGLE_FIELDS)}

      {canEdit && (
        <button
          onClick={handleSave}
          disabled={submitting || edits.length === 0}
          className="rounded-sm bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
        >
          {submitting ? 'Saving…' : edits.length > 0 ? `Save ${edits.length} Change(s)` : 'No Changes'}
        </button>
      )}
    </div>
  );
}
