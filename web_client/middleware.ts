import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const session = request.cookies.get('session')?.value;
  const path = request.nextUrl.pathname;

  // 1. Allow public access to specific league detail pages (e.g., /leagues/abc1234)
  // But protect the leagues list (/leagues), creation (/leagues/create), and admin routes.
  const isPublicLeagueView = path.match(/^\/leagues\/[^/]+$/);

  if (
    (path.startsWith('/leagues') && !isPublicLeagueView) || 
    path.startsWith('/dashboard') || 
    path.startsWith('/profile') ||
    path.startsWith('/master-leagues/create')
  ) {
    if (!session) {
      // 2. Pass the exact path they were trying to visit so the login page can redirect them back perfectly!
      const loginUrl = new URL('/login', request.url);
      loginUrl.searchParams.set('redirect', path);
      return NextResponse.redirect(loginUrl);
    }
  }

  return NextResponse.next();
}

export const config = {
  // Only run the middleware on routes that actually need protection to keep the app blazing fast
  matcher: ['/leagues/:path*', '/dashboard/:path*', '/profile/:path*', '/master-leagues/:path*'],
};
