import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { setFootballNewsApiKey } from '@/lib/repositories/footballNewsAdminRepository';

export async function PATCH(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const actor = { uid: identity!.uid, email: identity!.email };

    if (typeof body?.gnewsApiKey !== 'string') {
      return NextResponse.json({ error: 'gnewsApiKey (string) is required.' }, { status: 400 });
    }
    const key = body.gnewsApiKey.trim();
    if (!key) {
      return NextResponse.json({ error: 'API key cannot be empty.' }, { status: 400 });
    }
    const apiKeyStatus = await setFootballNewsApiKey(key, actor);
    return NextResponse.json({ apiKeyStatus });
  } catch (err) {
    console.error('[football-news settings update]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
