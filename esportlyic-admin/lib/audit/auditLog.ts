// lib/audit/auditLog.ts
//
// The audit trail for every admin action taken through this workspace.
// Generalizes the pattern already used by AdminService.createPointAdjustment
// in the mobile app (an immutable, actor-stamped write) into a single
// shared collection covering every module.
//
// recordAuditLog() deliberately never throws — a logging failure must
// never roll back or block the underlying admin action it's describing.
// It's called AFTER the action already succeeded, so failure here only
// means a missing log entry, not a missing/incorrect real-world change.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import type { AuditLogEntry } from '@/types/auditLog';

const COLLECTION = 'audit_logs';

export async function recordAuditLog(params: {
  actorUid: string;
  actorEmail?: string | null;
  action: string;
  targetType: string;
  targetId: string;
  summary: string;
}): Promise<void> {
  try {
    await adminDb.collection(COLLECTION).add({
      actorUid: params.actorUid,
      actorEmail: params.actorEmail ?? null,
      action: params.action,
      targetType: params.targetType,
      targetId: params.targetId,
      summary: params.summary,
      createdAtMs: Date.now(),
    });
  } catch (err) {
    console.error('[audit log] failed to record entry', err);
  }
}

export async function listAuditLogs(limit = 200): Promise<AuditLogEntry[]> {
  const snap = await adminDb.collection(COLLECTION).orderBy('createdAtMs', 'desc').limit(limit).get();
  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      actorUid: data.actorUid ?? '',
      actorEmail: data.actorEmail ?? null,
      action: data.action ?? '',
      targetType: data.targetType ?? '',
      targetId: data.targetId ?? '',
      summary: data.summary ?? '',
      createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    };
  });
}
