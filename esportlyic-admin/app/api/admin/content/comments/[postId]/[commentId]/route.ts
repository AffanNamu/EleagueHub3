import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { softDeleteComment, ContentModerationError } from '@/lib/repositories/contentAdminRepository';

export async function DELETE(
  _request: Request,
  { params }: { params: { postId: string; commentId: string } },
) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'content.moderate')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await softDeleteComment({
      postId: params.postId,
      commentId: params.commentId,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof ContentModerationError) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('[remove comment]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
