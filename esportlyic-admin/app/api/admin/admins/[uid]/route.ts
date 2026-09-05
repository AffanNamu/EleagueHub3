import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { updateAdminUser, removeAdminUser, AdminUserError } from '@/lib/repositories/adminUsersRepository';

export async function PATCH(request: Request, { params }: { params: { uid: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    await updateAdminUser(params.uid, {
      roleIds: Array.isArray(body?.roleIds) ? body.roleIds : [],
      grantLegacyPricingAdmin: body?.grantLegacyPricingAdmin === true,
      actorUid: identity.uid,
      actorEmail: identity.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminUserError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[update admin]', err);
    return NextResponse.json({ error: 'Something went wrong.' }, { status: 500 });
  }
}

export async function DELETE(_request: Request, { params }: { params: { uid: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await removeAdminUser(params.uid, { uid: identity.uid, email: identity.email });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminUserError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[remove admin]', err);
    return NextResponse.json({ error: 'Something went wrong.' }, { status: 500 });
  }
}
