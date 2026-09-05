import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { createPointAdjustment, MatchCorrectionError } from '@/lib/repositories/matchesAdminRepository';

export async function POST(request: Request, { params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    await createPointAdjustment({
      leagueId: params.leagueId,
      teamId: body?.teamId ?? '',
      type: body?.type === 'DEDUCTION' ? 'DEDUCTION' : 'ADDITION',
      points: Number(body?.points),
      reason: body?.reason ?? '',
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof MatchCorrectionError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[create point adjustment]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
