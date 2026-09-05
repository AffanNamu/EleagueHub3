import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { correctFixtureScore, MatchCorrectionError } from '@/lib/repositories/matchesAdminRepository';

export async function PATCH(
  request: Request,
  { params }: { params: { leagueId: string; matchId: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    await correctFixtureScore({
      leagueId: params.leagueId,
      matchId: params.matchId,
      homeScore: Number(body?.homeScore),
      awayScore: Number(body?.awayScore),
      status: body?.status,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof MatchCorrectionError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[correct fixture score]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
