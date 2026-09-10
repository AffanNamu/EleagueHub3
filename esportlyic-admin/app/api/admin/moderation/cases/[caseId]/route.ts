import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { addCaseNote, resolveCase, ModerationCaseError } from '@/lib/repositories/moderationCasesAdminRepository';

export async function PATCH(request: Request, { params }: { params: { caseId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'moderation_cases.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const actor = { actorUid: identity!.uid, actorName: identity!.email ?? identity!.uid, actorEmail: identity!.email };

    if (body?.action === 'note') {
      await addCaseNote({ caseId: params.caseId, text: body?.text ?? '', ...actor });
    } else if (body?.action === 'resolve') {
      const status = ['resolved', 'dismissed', 'appealed'].includes(body?.status) ? body.status : undefined;
      if (!status) return NextResponse.json({ error: 'Invalid status.' }, { status: 400 });
      await resolveCase({
        caseId: params.caseId,
        status,
        decision: body?.decision ?? '',
        actionTaken: body?.actionTaken ?? '',
        ...actor,
      });
    } else {
      return NextResponse.json({ error: 'Invalid action.' }, { status: 400 });
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof ModerationCaseError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[update moderation case]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
