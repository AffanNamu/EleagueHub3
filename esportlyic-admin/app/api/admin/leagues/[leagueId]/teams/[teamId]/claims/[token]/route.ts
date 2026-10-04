import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { revokeClaim, TeamAdminError } from '@/lib/repositories/teamsAdminRepository';

export async function DELETE(
  _request: Request,
  { params }: { params: { leagueId: string; teamId: string; token: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await revokeClaim(params.leagueId, params.teamId, params.token, {
      uid: identity!.uid,
      email: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof TeamAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[revoke claim]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
