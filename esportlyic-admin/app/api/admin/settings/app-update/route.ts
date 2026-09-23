import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import {
  getAppUpdateConfig,
  updateAppUpdateConfig,
  AppUpdateConfigError,
} from '@/lib/repositories/appUpdateAdminRepository';
import type { AppUpdateConfigEdit } from '@/types/appUpdateConfig';

const EDITABLE_KEYS = new Set<keyof AppUpdateConfigEdit>([
  'latestBuildNumber',
  'latestVersionName',
  'forceUpdate',
  'releaseNotes',
  'playStoreUrl',
  'appStoreUrl',
]);

export async function GET() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const config = await getAppUpdateConfig();
  return NextResponse.json({ config });
}

export async function PATCH(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'settings.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const rawEdit = (body?.edit ?? {}) as Record<string, unknown>;
    const edit: AppUpdateConfigEdit = {};

    for (const key of Object.keys(rawEdit)) {
      if (!EDITABLE_KEYS.has(key as keyof AppUpdateConfigEdit)) {
        return NextResponse.json({ error: `Unknown field "${key}".` }, { status: 400 });
      }
      (edit as Record<string, unknown>)[key] = rawEdit[key];
    }

    await updateAppUpdateConfig({
      edit,
      actorUid: identity!.uid,
      actorEmail: identity!.email,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof AppUpdateConfigError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[update app-update config]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
