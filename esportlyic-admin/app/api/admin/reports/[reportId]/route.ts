import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { reviewReport, ReportReviewError } from '@/lib/repositories/reportsAdminRepository';

export async function POST(request: Request, { params }: { params: { reportId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'reports.review')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  let decision: 'reviewed' | 'dismissed' | undefined;
  try {
    const body = await request.json();
    decision = body?.decision === 'reviewed' || body?.decision === 'dismissed' ? body.decision : undefined;
  } catch {
    return NextResponse.json({ error: 'Invalid request body.' }, { status: 400 });
  }

  if (!decision) {
    return NextResponse.json({ error: 'Missing or invalid decision.' }, { status: 400 });
  }

  try {
    await reviewReport({
      reportId: params.reportId,
      decision,
      reviewerUid: identity!.uid,
      reviewerEmail: identity!.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof ReportReviewError) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('[report review]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
