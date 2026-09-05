import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { correctKnockoutScore, MatchCorrectionError } from '@/lib/repositories/matchesAdminRepository';

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
    await correctKnockoutScore({
      leagueId: params.leagueId,
      matchId: params.matchId,
      homeScore: Number(body?.homeScore),
      awayScore: Number(body?.awayScore),
      status: body?.status,
      tiebreakWinnerTeamId: typeof body?.tiebreakWinnerTeamId === 'string' ? body.tiebreakWinnerTeamId : null,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof MatchCorrectionError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[correct knockout score]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
