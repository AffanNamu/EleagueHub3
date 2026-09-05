import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import {
  grantEntitlementOverride,
  revokeEntitlementOverride,
  EntitlementOverrideError,
} from '@/lib/repositories/entitlementAdminRepository';

export async function POST(request: Request, { params }: { params: { userId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    await grantEntitlementOverride({
      userId: params.userId,
      plan: body?.plan ?? '',
      duration: body?.duration ?? '',
      expiresAtMs: typeof body?.expiresAtMs === 'number' ? body.expiresAtMs : NaN,
      actorUid: identity.uid,
      actorEmail: identity.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof EntitlementOverrideError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[grant entitlement override]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}

export async function DELETE(_request: Request, { params }: { params: { userId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await revokeEntitlementOverride({ userId: params.userId, actorUid: identity.uid, actorEmail: identity.email });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof EntitlementOverrideError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[revoke entitlement override]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
