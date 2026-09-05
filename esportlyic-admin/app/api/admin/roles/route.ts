// app/api/admin/roles/route.ts
//
// Roles management is Super Admin-only (roles.manage is a superAdminOnly
// permission by design — it can't be delegated).

import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { listRoles, createRole, AdminRoleError } from '@/lib/repositories/adminRolesRepository';

export async function GET() {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const roles = await listRoles();
  return NextResponse.json({ roles });
}

export async function POST(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!identity?.isSuperAdmin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const role = await createRole({
      name: body?.name ?? '',
      description: body?.description ?? '',
      permissions: Array.isArray(body?.permissions) ? body.permissions : [],
      createdBy: identity.uid,
      createdByEmail: identity.email,
    });
    return NextResponse.json({ role });
  } catch (err) {
    if (err instanceof AdminRoleError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[create role]', err);
    return NextResponse.json({ error: 'Something went wrong.' }, { status: 500 });
  }
}
