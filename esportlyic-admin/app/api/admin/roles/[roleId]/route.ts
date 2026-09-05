import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { updateRole, deleteRole, AdminRoleError } from '@/lib/repositories/adminRolesRepository';

export async function PATCH(request: Request, { params }: { params: { roleId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    await updateRole(params.roleId, {
      name: body?.name ?? '',
      description: body?.description ?? '',
      permissions: Array.isArray(body?.permissions) ? body.permissions : [],
      actorUid: identity.uid,
      actorEmail: identity.email,
    });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminRoleError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[update role]', err);
    return NextResponse.json({ error: 'Something went wrong.' }, { status: 500 });
  }
}

export async function DELETE(_request: Request, { params }: { params: { roleId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await deleteRole(params.roleId, { uid: identity.uid, email: identity.email });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AdminRoleError) {
      return NextResponse.json({ error: err.message }, { status: 409 });
    }
    console.error('[delete role]', err);
    return NextResponse.json({ error: 'Something went wrong.' }, { status: 500 });
  }
}
