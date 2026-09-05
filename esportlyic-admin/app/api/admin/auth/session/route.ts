// app/api/admin/auth/session/route.ts
//
// Exchanges a Firebase ID token (from client-side sign-in) for an
// HttpOnly session cookie, AFTER verifying the signed-in user is either
// the super admin or listed in app/admins.pricingAdmins[]. This is the
// single choke point that decides who gets into the admin workspace —
// deliberately server-side only, using firebase-admin, so it cannot be
// bypassed by editing client code.

import { NextResponse } from 'next/server';
import { adminAuth, adminDb } from '@/lib/firebase-admin';
import { SUPER_ADMIN_UID, SESSION_COOKIE_NAME } from '@/lib/auth/adminAuthService';

const SESSION_EXPIRES_IN_MS = 5 * 24 * 60 * 60 * 1000; // 5 days

function looksLikeFirebaseUid(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 20;
}

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
  try {
    const decoded = await adminAuth.verifyIdToken(idToken, true);
    uid = decoded.uid;
  } catch {
    return NextResponse.json({ error: 'Invalid or expired sign-in. Please try again.' }, { status: 401 });
  }

  const isSuperAdmin = uid === SUPER_ADMIN_UID;

  let isPlatformAdmin = isSuperAdmin;
  if (!isPlatformAdmin) {
    const adminsSnap = await adminDb.collection('app').doc('admins').get();
    const pricingAdmins = adminsSnap.exists ? adminsSnap.data()?.pricingAdmins : undefined;
    if (Array.isArray(pricingAdmins)) {
      isPlatformAdmin = pricingAdmins.filter(looksLikeFirebaseUid).map((v) => v.trim()).includes(uid);
    }
  }

  if (!isPlatformAdmin) {
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
