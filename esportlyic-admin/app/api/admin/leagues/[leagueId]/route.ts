import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { updateLeague, deleteLeague, LeagueAdminError } from '@/lib/repositories/leaguesAdminRepository';
import type { LeagueInput } from '@/types/league';

function parseInput(body: unknown): LeagueInput {
  const b = (body ?? {}) as Record<string, unknown>;
  return {
    name: typeof b.name === 'string' ? b.name : '',
    description: typeof b.description === 'string' ? b.description : '',
    isPrivate: b.isPrivate === true,
    region: typeof b.region === 'string' ? b.region : '',
    season: typeof b.season === 'string' ? b.season : '',
    leagueImageUrl: typeof b.leagueImageUrl === 'string' ? b.leagueImageUrl : '',
    sponsorImageUrl: typeof b.sponsorImageUrl === 'string' ? b.sponsorImageUrl : '',
  };
}

export async function PATCH(request: Request, { params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const league = await updateLeague(params.leagueId, parseInput(body), {
      uid: identity!.uid,
      email: identity!.email,
    });
    return NextResponse.json({ league });
  } catch (err) {
    if (err instanceof LeagueAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[update league]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}

export async function DELETE(_request: Request, { params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await deleteLeague(params.leagueId, { uid: identity!.uid, email: identity!.email });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof LeagueAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[delete league]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
