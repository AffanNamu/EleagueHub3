import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { setAccountSuspension, AccountSuspensionError } from '@/lib/repositories/usersAdminRepository';

export async function POST(request: Request, { params }: { params: { userId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'users.suspend')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const suspended = body?.suspended === true;
    const reason = typeof body?.reason === 'string' ? body.reason : '';

    await setAccountSuspension({
      userId: params.userId,
      suspended,
      reason,
      updatedBy: identity!.uid,
      updatedByEmail: identity!.email,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AccountSuspensionError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[account suspension]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
