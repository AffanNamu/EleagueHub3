import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { refundPayment, PaymentRefundError } from '@/lib/repositories/paymentRefundsAdminRepository';

export async function POST(request: Request, { params }: { params: { paymentId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'payments.refund')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json().catch(() => ({}));
    const reason = typeof body.reason === 'string' ? body.reason : '';
    const revokeAccess = body.revokeAccess === true;

    const result = await refundPayment({
      paymentId: params.paymentId,
      reason,
      revokeAccess,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });

    return NextResponse.json({ ok: true, revokedEntitlement: result.revokedEntitlement });
  } catch (err) {
    if (err instanceof PaymentRefundError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[refund payment]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
