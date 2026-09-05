// lib/repositories/pricingConfigAdminRepository.ts
//
// Server-only reader/writer for app/pricing — the SAME document
// pricing_admin_screen.dart edits from the mobile app. Reads and writes
// only primitive-valued fields (number/boolean/string) that already
// exist on the document; never adds or removes keys, since this
// workspace doesn't have full certainty on every field the mobile app
// expects to find there.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { PricingConfig, PricingConfigField, PricingFieldValue } from '@/types/pricingConfig';

const DOC_PATH = { collection: 'app', doc: 'pricing' };

export async function getPricingConfig(): Promise<PricingConfig> {
  const snap = await adminDb.collection(DOC_PATH.collection).doc(DOC_PATH.doc).get();
  const data = snap.exists ? snap.data() ?? {} : {};

  const fields: PricingConfigField[] = [];
  const unsupportedKeys: string[] = [];

  for (const [key, value] of Object.entries(data)) {
    if (typeof value === 'number') {
      fields.push({ key, value, type: 'number' });
    } else if (typeof value === 'boolean') {
      fields.push({ key, value, type: 'boolean' });
    } else if (typeof value === 'string') {
      fields.push({ key, value, type: 'string' });
    } else {
      unsupportedKeys.push(key);
    }
  }

  fields.sort((a, b) => a.key.localeCompare(b.key));

  return { fields, unsupportedKeys };
}

export class PricingConfigError extends Error {}

export async function updatePricingConfig(params: {
  updates: Record<string, PricingFieldValue>;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection(DOC_PATH.collection).doc(DOC_PATH.doc);
  const snap = await ref.get();

  if (!snap.exists) {
    throw new PricingConfigError('app/pricing document does not exist.');
  }

  const existing = snap.data() ?? {};

  // Guard: only allow updating keys that already exist with a matching
  // primitive type — prevents accidentally introducing a field the
  // mobile app doesn't expect, or changing a field's type out from
  // under it.
  for (const [key, value] of Object.entries(params.updates)) {
    if (!(key in existing)) {
      throw new PricingConfigError(`"${key}" does not exist on the pricing document.`);
    }
    const existingType = typeof existing[key];
    if (existingType !== typeof value) {
      throw new PricingConfigError(`"${key}" expects a ${existingType}, got ${typeof value}.`);
    }
  }

  await ref.update(params.updates);

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'pricing.update',
    targetType: 'pricing_config',
    targetId: 'app/pricing',
    summary: `Updated pricing fields: ${Object.keys(params.updates).join(', ')}`,
  });
}
