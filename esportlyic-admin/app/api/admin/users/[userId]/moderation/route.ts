import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { setChatModeration, setGlobalChatAdmin } from '@/lib/repositories/usersAdminRepository';

export async function POST(request: Request, { params }: { params: { userId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'users.moderate')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();

    if (typeof body?.muted === 'boolean' || typeof body?.banned === 'boolean') {
      await setChatModeration({
        userId: params.userId,
        muted: body.muted === true,
        banned: body.banned === true,
        updatedBy: identity!.uid,
        updatedByEmail: identity!.email,
      });
    }

    if (typeof body?.isGlobalChatAdmin === 'boolean') {
      await setGlobalChatAdmin({
        userId: params.userId,
        isAdmin: body.isGlobalChatAdmin,
        updatedBy: identity!.uid,
        updatedByEmail: identity!.email,
      });
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error('[user moderation]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
