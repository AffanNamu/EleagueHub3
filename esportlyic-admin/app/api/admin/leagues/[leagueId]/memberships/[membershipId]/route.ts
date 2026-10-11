import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { assignMemberToTeam, removeMemberFromTeam, TeamAdminError } from '@/lib/repositories/teamsAdminRepository';

export async function PATCH(
  request: Request,
  { params }: { params: { leagueId: string; membershipId: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const body = await request.json().catch(() => ({}) as Record<string, unknown>);
  const teamId = typeof body.teamId === 'string' ? body.teamId : '';

  try {
    await assignMemberToTeam(params.leagueId, params.membershipId, teamId, {
      uid: identity!.uid,
      email: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof TeamAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[assign team member]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: { leagueId: string; membershipId: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await removeMemberFromTeam(params.leagueId, params.membershipId, {
      uid: identity!.uid,
      email: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof TeamAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[remove team member]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
