import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { createCase, ModerationCaseError } from '@/lib/repositories/moderationCasesAdminRepository';

export async function POST(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'moderation_cases.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const newCase = await createCase({
      targetUserId: body?.targetUserId ?? '',
      targetUserName: body?.targetUserName ?? '',
      reason: body?.reason ?? '',
      linkedEvidence: Array.isArray(body?.linkedEvidence) ? body.linkedEvidence : [],
      actorUid: identity!.uid,
      actorName: identity!.email ?? identity!.uid,
      actorEmail: identity!.email,
    });
    return NextResponse.json({ case: newCase });
  } catch (err) {
    if (err instanceof ModerationCaseError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[create moderation case]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
