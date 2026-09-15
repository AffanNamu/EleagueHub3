import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import {
  bulkReviewGlobalChatRequests,
  GlobalChatRequestReviewError,
} from '@/lib/repositories/globalChatRequestsAdminRepository';

export async function POST(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'global_chat_requests.review')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  let uids: string[];
  let decision: 'approved' | 'rejected' | undefined;
  try {
    const body = await request.json();
    uids = Array.isArray(body?.uids) ? body.uids.filter((id: unknown) => typeof id === 'string') : [];
    decision = body?.decision === 'approved' || body?.decision === 'rejected' ? body.decision : undefined;
  } catch {
    return NextResponse.json({ error: 'Invalid request body.' }, { status: 400 });
  }

  if (!decision) {
    return NextResponse.json({ error: 'Missing or invalid decision.' }, { status: 400 });
  }

  try {
    const result = await bulkReviewGlobalChatRequests({
      uids,
      decision,
      reviewerUid: identity!.uid,
      reviewerEmail: identity!.email,
    });
    return NextResponse.json({ ok: true, ...result });
  } catch (err) {
    if (err instanceof GlobalChatRequestReviewError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[bulk global chat request review]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
