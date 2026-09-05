import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { softDeleteReply, DiscussionModerationError } from '@/lib/repositories/discussionsAdminRepository';

export async function DELETE(
  _request: Request,
  { params }: { params: { threadId: string; replyId: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'content.moderate')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await softDeleteReply({
      threadId: params.threadId,
      replyId: params.replyId,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof DiscussionModerationError) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('[remove discussion reply]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
