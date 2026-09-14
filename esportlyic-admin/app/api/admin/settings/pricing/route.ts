import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { getPricingConfig, updatePricingConfig, PricingConfigError } from '@/lib/repositories/pricingConfigAdminRepository';
import type { PricingFieldEdit } from '@/types/pricingConfig';

export async function GET() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'pricing.view')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const config = await getPricingConfig();
  return NextResponse.json({ config });
}

function isValidEdit(e: unknown): e is PricingFieldEdit {
  if (!e || typeof e !== 'object') return false;
  const edit = e as Record<string, unknown>;
  return (
    (edit.currency === 'ngn' || edit.currency === 'usd') &&
    typeof edit.key === 'string' &&
    (typeof edit.value === 'number' || typeof edit.value === 'boolean' || edit.value === null)
  );
}

export async function PATCH(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'pricing.edit')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const rawEdits = Array.isArray(body?.edits) ? body.edits : [];
    const edits = rawEdits.filter(isValidEdit);

    if (edits.length !== rawEdits.length) {
      return NextResponse.json({ error: 'Malformed pricing edit payload.' }, { status: 400 });
    }

    await updatePricingConfig({
      edits,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof PricingConfigError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[update pricing]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
