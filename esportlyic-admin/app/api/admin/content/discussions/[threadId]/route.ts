import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { softDeleteThread, DiscussionModerationError } from '@/lib/repositories/discussionsAdminRepository';

export async function DELETE(_request: Request, { params }: { params: { threadId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'content.moderate')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await softDeleteThread({ threadId: params.threadId, actorUid: identity!.uid, actorEmail: identity!.email });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof DiscussionModerationError) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('[remove discussion thread]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
