// app/api/admin/auth/session/route.ts
//
// Exchanges a Firebase ID token (from client-side sign-in) for an
// HttpOnly session cookie, AFTER verifying the signed-in user actually
// has admin access — super admin, legacy app/admins.pricingAdmins[], OR
// a granular admin_users/{uid} role assignment (see resolveIdentity() in
// adminAuthService.ts, the single shared source of truth for all three
// tiers — this route used to check only the first two, which locked out
// every admin added purely through the newer role-based system). This
// is the single choke point that decides who gets into the admin
// workspace — deliberately server-side only, using firebase-admin, so
// it cannot be bypassed by editing client code.

import { NextResponse } from 'next/server';
import { adminAuth } from '@/lib/firebase-admin';
import { resolveIdentity, SESSION_COOKIE_NAME } from '@/lib/auth/adminAuthService';

const SESSION_EXPIRES_IN_MS = 5 * 24 * 60 * 60 * 1000; // 5 days

export async function POST(request: Request) {
  let idToken: string | undefined;

  try {
    const body = await request.json();
    idToken = typeof body?.idToken === 'string' ? body.idToken : undefined;
  } catch {
    return NextResponse.json({ error: 'Invalid request body.' }, { status: 400 });
  }

  if (!idToken) {
    return NextResponse.json({ error: 'Missing ID token.' }, { status: 400 });
  }

  let uid: string;
  let email: string | null;
  try {
    const decoded = await adminAuth.verifyIdToken(idToken, true);
    uid = decoded.uid;
    email = decoded.email ?? null;
  } catch {
    return NextResponse.json({ error: 'Invalid or expired sign-in. Please try again.' }, { status: 401 });
  }

  const identity = await resolveIdentity(uid, email);

  if (!identity.isSuperAdmin && !identity.isLegacyFullAccess && !identity.isPlatformAdmin) {
    return NextResponse.json(
      { error: 'This account does not have access to the operations workspace.' },
      { status: 403 },
    );
  }

  const sessionCookie = await adminAuth.createSessionCookie(idToken, {
    expiresIn: SESSION_EXPIRES_IN_MS,
  });

  const response = NextResponse.json({ ok: true });
  response.cookies.set(SESSION_COOKIE_NAME, sessionCookie, {
    maxAge: SESSION_EXPIRES_IN_MS / 1000,
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/',
  });

  return response;
}

export async function DELETE() {
  const response = NextResponse.json({ ok: true });
  response.cookies.set(SESSION_COOKIE_NAME, '', { maxAge: 0, path: '/' });
  return response;
}
