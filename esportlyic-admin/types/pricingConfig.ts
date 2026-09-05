// types/pricingConfig.ts
//
// Deliberately loose. app/pricing's exact field set was never fully
// confirmed against pricing_admin_screen.dart's controller names — rather
// than hardcode a guessed schema, this type reflects whatever primitive
// fields actually exist in the live document.

export type PricingFieldValue = number | boolean | string;

export interface PricingConfigField {
  key: string;
  value: PricingFieldValue;
  type: 'number' | 'boolean' | 'string';
}

export interface PricingConfig {
  fields: PricingConfigField[];
  /** Any keys whose value is an object/array — shown read-only, not editable here. */
  unsupportedKeys: string[];
}
