import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const session = request.cookies.get('session')?.value;

  // Protect dashboard routes
  if (request.nextUrl.pathname.startsWith('/leagues') || request.nextUrl.pathname === '/') {
    if (!session) {
      return NextResponse.redirect(new URL('/login', request.url));
    }
  }

  // Redirect authenticated users away from login
  if (request.nextUrl.pathname.startsWith('/login')) {
    if (session) {
      return NextResponse.redirect(new URL('/leagues', request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/', '/leagues/:path*', '/login', '/profile/:path*'],
};
