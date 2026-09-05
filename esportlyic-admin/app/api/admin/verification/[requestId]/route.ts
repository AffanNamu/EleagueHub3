import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import {
  reviewVerificationRequest,
  VerificationReviewError,
} from '@/lib/repositories/verificationAdminRepository';
import type { ReviewAction } from '@/types/verification';

const VALID_ACTIONS: ReviewAction[] = ['approve', 'reject', 'request_info'];

export async function POST(request: Request, { params }: { params: { requestId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'verification.review')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  let action: ReviewAction | undefined;
  let note = '';

  try {
    const body = await request.json();
    action = VALID_ACTIONS.includes(body?.action) ? body.action : undefined;
    note = typeof body?.note === 'string' ? body.note : '';
  } catch {
    return NextResponse.json({ error: 'Invalid request body.' }, { status: 400 });
  }

  if (!action) {
    return NextResponse.json({ error: 'Missing or invalid action.' }, { status: 400 });
  }

  try {
    await reviewVerificationRequest({
      requestId: params.requestId,
      action,
      note,
      reviewerUid: identity!.uid,
      reviewerEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof VerificationReviewError) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('[verification review]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
