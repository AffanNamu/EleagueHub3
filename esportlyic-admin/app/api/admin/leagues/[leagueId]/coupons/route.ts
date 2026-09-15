import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { setLeagueCouponsEnabled, CouponAdminError } from '@/lib/repositories/couponsAdminRepository';

export async function PATCH(request: Request, { params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const enabled = body.enabled === true;

    await setLeagueCouponsEnabled(params.leagueId, enabled, {
      uid: identity!.uid,
      email: identity!.email,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof CouponAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[toggle league coupons]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
