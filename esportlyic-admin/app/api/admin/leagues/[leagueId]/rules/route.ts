import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { getCompetitionRules, updateCompetitionRules } from '@/lib/repositories/competitionRulesAdminRepository';

export async function GET(_request: Request, { params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.view')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const rules = await getCompetitionRules(params.leagueId);
  return NextResponse.json({ rules });
}

export async function PATCH(request: Request, { params }: { params: { leagueId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'leagues.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const rules = await updateCompetitionRules({
      leagueId: params.leagueId,
      updates: body?.updates ?? {},
      actorUid: identity!.uid,
      actorEmail: identity!.email,
      actorName: identity!.email ?? identity!.uid,
    });
    return NextResponse.json({ rules });
  } catch (err) {
    console.error('[update competition rules]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
