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

function toAuditLogEntry(id: string, data: FirebaseFirestore.DocumentData): AuditLogEntry {
  return {
    id,
    actorUid: data.actorUid ?? '',
    actorEmail: data.actorEmail ?? null,
    action: data.action ?? '',
    targetType: data.targetType ?? '',
    targetId: data.targetId ?? '',
    summary: data.summary ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
  };
}

export async function listAuditLogs(limit = 200): Promise<AuditLogEntry[]> {
  const snap = await adminDb.collection(COLLECTION).orderBy('createdAtMs', 'desc').limit(limit).get();
  return snap.docs.map((doc) => toAuditLogEntry(doc.id, doc.data()));
}

/**
 * Exact-action lookup -- used to derive a feature's own history from the
 * shared audit trail instead of standing up a dedicated collection for
 * it. Every action string used this way is a single literal (e.g.
 * 'notification.send'), not a prefix, so it only ever returns exact
 * matches. NOTE: an equality filter plus an orderBy on a different field
 * DOES require a composite index in Firestore (action ASC, createdAtMs
 * DESC -- see firestore.indexes.json) despite this only being two
 * "simple" clauses; a caller adding a new action string doesn't need a
 * new index (Firestore doesn't index by literal value), but the index
 * itself must exist and be deployed for this function to work at all.
 */
export async function listAuditLogsByAction(action: string, limit = 50): Promise<AuditLogEntry[]> {
  const snap = await adminDb
    .collection(COLLECTION)
    .where('action', '==', action)
    .orderBy('createdAtMs', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((doc) => toAuditLogEntry(doc.id, doc.data()));
}
