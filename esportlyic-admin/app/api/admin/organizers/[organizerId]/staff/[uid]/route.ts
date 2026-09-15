import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import {
  removeMasterLeagueStaff,
  MasterLeagueStaffError,
} from '@/lib/repositories/masterLeagueStaffAdminRepository';

export async function DELETE(
  request: Request,
  { params }: { params: { organizerId: string; uid: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'organizers.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await removeMasterLeagueStaff({
      masterLeagueId: params.organizerId,
      targetUid: params.uid,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof MasterLeagueStaffError) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('[master league staff remove]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
