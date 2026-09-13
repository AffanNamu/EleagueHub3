import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { createHomeContent, listHomeContent, HomeContentError } from '@/lib/repositories/homeContentAdminRepository';
import type { HomeContentInput } from '@/types/homeContent';

function parseInput(body: unknown): HomeContentInput {
  const b = (body ?? {}) as Record<string, unknown>;
  return {
    type: b.type as HomeContentInput['type'],
    title: typeof b.title === 'string' ? b.title : '',
    subtitle: typeof b.subtitle === 'string' ? b.subtitle : '',
    imageUrl: typeof b.imageUrl === 'string' ? b.imageUrl : '',
    ctaLabel: typeof b.ctaLabel === 'string' ? b.ctaLabel : '',
    ctaDestinationType: b.ctaDestinationType as HomeContentInput['ctaDestinationType'],
    ctaLeagueId: typeof b.ctaLeagueId === 'string' ? b.ctaLeagueId : undefined,
    ctaFixedRoute: typeof b.ctaFixedRoute === 'string' ? b.ctaFixedRoute : undefined,
    severity: (b.severity as HomeContentInput['severity']) ?? 'info',
    active: b.active === true,
    order: typeof b.order === 'number' ? b.order : 0,
    startAtMs: typeof b.startAtMs === 'number' ? b.startAtMs : null,
    endAtMs: typeof b.endAtMs === 'number' ? b.endAtMs : null,
  };
}

export async function GET() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'home_content.view')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const items = await listHomeContent();
  return NextResponse.json({ items });
}

export async function POST(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'home_content.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const item = await createHomeContent(parseInput(body), { uid: identity!.uid, email: identity!.email });
    return NextResponse.json({ item });
  } catch (err) {
    if (err instanceof HomeContentError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[create home content]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
