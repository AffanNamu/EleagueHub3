import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { getPricingConfig, updatePricingConfig, PricingConfigError } from '@/lib/repositories/pricingConfigAdminRepository';

export async function GET() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'pricing.view')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const config = await getPricingConfig();
  return NextResponse.json({ config });
}

export async function PATCH(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'pricing.edit')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const updates = body?.updates && typeof body.updates === 'object' ? body.updates : {};

    await updatePricingConfig({
      updates,
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
