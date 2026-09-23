// lib/repositories/appUpdateAdminRepository.ts
//
// Server-only reader/writer for app_config/app_update -- the doc the
// Flutter app's AuthRouterRefresh (lib/core/routing/app_router.dart)
// watches live to decide whether the installed build is behind and, if
// so, whether that's a skippable nudge (forceUpdate: false) or a hard
// block that routes every screen to /force-update until the user
// updates (forceUpdate: true). Mobile-app-only -- the web app never
// reads this doc, and this page must never be wired into it.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { AppUpdateConfig, AppUpdateConfigEdit } from '@/types/appUpdateConfig';

const DOC = { collection: 'app_config', doc: 'app_update' } as const;

const DEFAULTS: AppUpdateConfig = {
  latestBuildNumber: 0,
  latestVersionName: '',
  forceUpdate: false,
  releaseNotes: '',
  playStoreUrl: '',
  appStoreUrl: '',
};

function merge(raw: Record<string, unknown> | undefined): AppUpdateConfig {
  const data = raw && typeof raw === 'object' ? raw : {};
  return {
    latestBuildNumber:
      typeof data.latestBuildNumber === 'number' && Number.isFinite(data.latestBuildNumber)
        ? data.latestBuildNumber
        : DEFAULTS.latestBuildNumber,
    latestVersionName: typeof data.latestVersionName === 'string' ? data.latestVersionName : DEFAULTS.latestVersionName,
    forceUpdate: typeof data.forceUpdate === 'boolean' ? data.forceUpdate : DEFAULTS.forceUpdate,
    releaseNotes: typeof data.releaseNotes === 'string' ? data.releaseNotes : DEFAULTS.releaseNotes,
    playStoreUrl: typeof data.playStoreUrl === 'string' ? data.playStoreUrl : DEFAULTS.playStoreUrl,
    appStoreUrl: typeof data.appStoreUrl === 'string' ? data.appStoreUrl : DEFAULTS.appStoreUrl,
  };
}

export async function getAppUpdateConfig(): Promise<AppUpdateConfig> {
  const snap = await adminDb.collection(DOC.collection).doc(DOC.doc).get();
  return merge(snap.exists ? snap.data() : undefined);
}

export class AppUpdateConfigError extends Error {}

function validate(edit: AppUpdateConfigEdit): void {
  if (edit.latestBuildNumber !== undefined) {
    if (!Number.isInteger(edit.latestBuildNumber) || edit.latestBuildNumber < 0) {
      throw new AppUpdateConfigError('"latestBuildNumber" must be a non-negative integer.');
    }
  }
  if (edit.latestVersionName !== undefined && typeof edit.latestVersionName !== 'string') {
    throw new AppUpdateConfigError('"latestVersionName" must be a string.');
  }
  if (edit.forceUpdate !== undefined && typeof edit.forceUpdate !== 'boolean') {
    throw new AppUpdateConfigError('"forceUpdate" must be a boolean.');
  }
  if (edit.releaseNotes !== undefined && typeof edit.releaseNotes !== 'string') {
    throw new AppUpdateConfigError('"releaseNotes" must be a string.');
  }
  if (edit.playStoreUrl !== undefined && typeof edit.playStoreUrl !== 'string') {
    throw new AppUpdateConfigError('"playStoreUrl" must be a string.');
  }
  if (edit.appStoreUrl !== undefined && typeof edit.appStoreUrl !== 'string') {
    throw new AppUpdateConfigError('"appStoreUrl" must be a string.');
  }
}

export async function updateAppUpdateConfig(params: {
  edit: AppUpdateConfigEdit;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  validate(params.edit);

  const ref = adminDb.collection(DOC.collection).doc(DOC.doc);
  await ref.set(
    { ...params.edit, updatedAtMs: Date.now(), updatedBy: params.actorUid },
    { merge: true },
  );

  const summary = Object.entries(params.edit)
    .map(([k, v]) => `${k}=${v}`)
    .join(', ');

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'app_update.update',
    targetType: 'app_update_config',
    targetId: `${DOC.collection}/${DOC.doc}`,
    summary: `Updated app update config: ${summary}`,
  });
}
