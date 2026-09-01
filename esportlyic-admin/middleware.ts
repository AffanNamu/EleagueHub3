// middleware.ts
//
// Edge-layer gate for the admin workspace. This is a FAST, coarse check
// (cookie presence only) meant to redirect unauthenticated visitors away
// from /(admin) routes before any page code runs. It is NOT the source of
// authorization truth — the real check (session validity + platform-admin
// status via Admin SDK) happens in app/(admin)/layout.tsx, which runs on
// the Node.js runtime where firebase-admin is available. Middleware runs
// on the Edge runtime and cannot use firebase-admin directly.

import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

const SESSION_COOKIE_NAME = 'nomad_admin_session';
const PUBLIC_PATHS = ['/login'];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isPublicPath = PUBLIC_PATHS.some((path) => pathname.startsWith(path));
  const sessionCookie = request.cookies.get(SESSION_COOKIE_NAME)?.value;

  if (!isPublicPath && !sessionCookie) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('next', pathname);
    return NextResponse.redirect(loginUrl);
  }

  if (isPublicPath && sessionCookie) {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    /*
     * Match everything except:
     * - api routes (session creation must be reachable while logged out)
     * - _next static/image internals
     * - favicon and other static assets
     */
    '/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|webp)$).*)',
  ],
};
