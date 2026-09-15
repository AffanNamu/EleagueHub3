import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { renameTeam, deleteTeam, TeamAdminError } from '@/lib/repositories/teamsAdminRepository';

export async function PATCH(
  request: Request,
  { params }: { params: { leagueId: string; teamId: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const name = typeof body.name === 'string' ? body.name : '';

    await renameTeam(params.leagueId, params.teamId, name, {
      uid: identity!.uid,
      email: identity!.email,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof TeamAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[rename team]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: { leagueId: string; teamId: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await deleteTeam(params.leagueId, params.teamId, { uid: identity!.uid, email: identity!.email });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof TeamAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[delete team]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
