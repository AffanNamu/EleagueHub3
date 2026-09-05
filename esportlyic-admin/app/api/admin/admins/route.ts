import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { listAdminUsers, addAdminUser, AdminUserError } from '@/lib/repositories/adminUsersRepository';

export async function GET() {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const admins = await listAdminUsers();
  return NextResponse.json({ admins });
}

export async function POST(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const admin = await addAdminUser({
      email: body?.email ?? '',
      roleIds: Array.isArray(body?.roleIds) ? body.roleIds : [],
      grantLegacyPricingAdmin: body?.grantLegacyPricingAdmin === true,
      addedBy: identity.uid,
    });
    return NextResponse.json({ admin });
  } catch (err) {
    if (err instanceof AdminUserError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[add admin]', err);
    return NextResponse.json({ error: 'Something went wrong.' }, { status: 500 });
  }
}
