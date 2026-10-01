import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { setFootballHubPollerEnabled } from '@/lib/repositories/footballHubAdminRepository';

export async function PATCH(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    if (typeof body?.pollerEnabled !== 'boolean') {
      return NextResponse.json({ error: 'pollerEnabled must be a boolean.' }, { status: 400 });
    }

    const config = await setFootballHubPollerEnabled(body.pollerEnabled, {
      uid: identity!.uid,
      email: identity!.email,
    });

    return NextResponse.json({ config });
  } catch (err) {
    console.error('[football-hub poller toggle]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
