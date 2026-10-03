import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { setFootballHubPollerEnabled, setFootballHubApiKey } from '@/lib/repositories/footballHubAdminRepository';

export async function PATCH(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const actor = { uid: identity!.uid, email: identity!.email };

    if (typeof body?.pollerEnabled === 'boolean') {
      const config = await setFootballHubPollerEnabled(body.pollerEnabled, actor);
      return NextResponse.json({ config });
    }

    if (typeof body?.apiFootballKey === 'string') {
      const key = body.apiFootballKey.trim();
      if (!key) {
        return NextResponse.json({ error: 'API key cannot be empty.' }, { status: 400 });
      }
      const apiKeyStatus = await setFootballHubApiKey(key, actor);
      return NextResponse.json({ apiKeyStatus });
    }

    return NextResponse.json({ error: 'pollerEnabled (boolean) or apiFootballKey (string) is required.' }, { status: 400 });
  } catch (err) {
    console.error('[football-hub settings update]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
