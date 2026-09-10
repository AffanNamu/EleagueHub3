// lib/repositories/moderationCasesAdminRepository.ts
//
// New top-level collection: moderation_cases/{caseId}. Purely a company-
// side investigation layer over existing evidence (reports, content,
// chat requests) — nothing here duplicates or replaces those systems,
// it links to them by id/type.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { CaseStatus, LinkedEvidence, ModerationCase } from '@/types/moderationCase';

const COLLECTION = 'moderation_cases';

function toCase(id: string, data: FirebaseFirestore.DocumentData): ModerationCase {
  return {
    caseId: id,
    targetUserId: data.targetUserId ?? '',
    targetUserName: data.targetUserName ?? '',
    reason: data.reason ?? '',
    status: (data.status as CaseStatus) ?? 'open',
    openedBy: data.openedBy ?? '',
    openedByName: data.openedByName ?? '',
    openedAtMs: typeof data.openedAtMs === 'number' ? data.openedAtMs : 0,
    linkedEvidence: Array.isArray(data.linkedEvidence) ? data.linkedEvidence : [],
    notes: Array.isArray(data.notes) ? data.notes : [],
    decision: data.decision ?? '',
    actionTaken: data.actionTaken ?? '',
    resolvedAtMs: typeof data.resolvedAtMs === 'number' ? data.resolvedAtMs : 0,
    resolvedBy: data.resolvedBy ?? '',
  };
}

export async function listCases(statusFilter?: CaseStatus): Promise<ModerationCase[]> {
  let query: FirebaseFirestore.Query = adminDb.collection(COLLECTION);
  if (statusFilter) query = query.where('status', '==', statusFilter);
  const snap = await query.orderBy('openedAtMs', 'desc').limit(100).get();
  return snap.docs.map((doc) => toCase(doc.id, doc.data()));
}

export async function getCase(caseId: string): Promise<ModerationCase | null> {
  const snap = await adminDb.collection(COLLECTION).doc(caseId).get();
  if (!snap.exists) return null;
  return toCase(snap.id, snap.data() ?? {});
}

export class ModerationCaseError extends Error {}

export async function createCase(params: {
  targetUserId: string;
  targetUserName: string;
  reason: string;
  linkedEvidence: LinkedEvidence[];
  actorUid: string;
  actorName: string;
  actorEmail?: string | null;
}): Promise<ModerationCase> {
  if (!params.targetUserId.trim()) throw new ModerationCaseError('targetUserId is required.');
  if (!params.reason.trim()) throw new ModerationCaseError('A reason is required to open a case.');

  const nowMs = Date.now();
  const ref = adminDb.collection(COLLECTION).doc();

  const newCase: Omit<ModerationCase, 'caseId'> = {
    targetUserId: params.targetUserId,
    targetUserName: params.targetUserName,
    reason: params.reason.trim(),
    status: 'open',
    openedBy: params.actorUid,
    openedByName: params.actorName,
    openedAtMs: nowMs,
    linkedEvidence: params.linkedEvidence,
    notes: [],
    decision: '',
    actionTaken: '',
    resolvedAtMs: 0,
    resolvedBy: '',
  };

  await ref.set(newCase);

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'moderation_case.open',
    targetType: 'moderation_case',
    targetId: ref.id,
    summary: `Opened case against ${params.targetUserName || params.targetUserId} (${params.reason.trim()})`,
  });

  return { caseId: ref.id, ...newCase };
}

export async function addCaseNote(params: {
  caseId: string;
  text: string;
  actorUid: string;
  actorName: string;
  actorEmail?: string | null;
}): Promise<void> {
  if (!params.text.trim()) throw new ModerationCaseError('Note text is required.');

  const ref = adminDb.collection(COLLECTION).doc(params.caseId);
  const snap = await ref.get();
  if (!snap.exists) throw new ModerationCaseError('Case not found.');

  const note = {
    authorUid: params.actorUid,
    authorName: params.actorName,
    text: params.text.trim(),
    createdAtMs: Date.now(),
  };

  const existingNotes = Array.isArray(snap.data()?.notes) ? snap.data()!.notes : [];
  await ref.update({
    notes: [...existingNotes, note],
    status: snap.data()?.status === 'open' ? 'investigating' : snap.data()?.status,
  });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'moderation_case.note',
    targetType: 'moderation_case',
    targetId: params.caseId,
    summary: `Added investigation note to case ${params.caseId}`,
  });
}

export async function resolveCase(params: {
  caseId: string;
  status: 'resolved' | 'dismissed' | 'appealed';
  decision: string;
  actionTaken: string;
  actorUid: string;
  actorName: string;
  actorEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection(COLLECTION).doc(params.caseId);
  const snap = await ref.get();
  if (!snap.exists) throw new ModerationCaseError('Case not found.');

  await ref.update({
    status: params.status,
    decision: params.decision.trim(),
    actionTaken: params.actionTaken.trim(),
    resolvedAtMs: Date.now(),
    resolvedBy: params.actorUid,
  });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: `moderation_case.${params.status}`,
    targetType: 'moderation_case',
    targetId: params.caseId,
    summary: `Case ${params.caseId} marked ${params.status}: ${params.decision.trim() || 'no decision text'}`,
  });
}
