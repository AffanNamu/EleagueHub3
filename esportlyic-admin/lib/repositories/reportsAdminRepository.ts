// lib/repositories/reportsAdminRepository.ts

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { ReportStatus, UserReport } from '@/types/report';

const COLLECTION = 'reports';

function toUserReport(id: string, data: FirebaseFirestore.DocumentData): UserReport {
  return {
    reportId: id,
    reporterId: data.reporterId ?? '',
    targetUserId: data.targetUserId ?? '',
    reason: (data.reason as UserReport['reason']) ?? 'other',
    details: data.details ?? '',
    status: (data.status as ReportStatus) ?? 'pending',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    reviewedAtMs: typeof data.reviewedAtMs === 'number' ? data.reviewedAtMs : 0,
    reviewedBy: data.reviewedBy ?? '',
  };
}

export async function listReports(statusFilter?: ReportStatus): Promise<UserReport[]> {
  let query: FirebaseFirestore.Query = adminDb.collection(COLLECTION);
  if (statusFilter) query = query.where('status', '==', statusFilter);
  const snap = await query.orderBy('createdAtMs', 'desc').limit(100).get();
  return snap.docs.map((doc) => toUserReport(doc.id, doc.data()));
}

export async function getReport(reportId: string): Promise<UserReport | null> {
  const snap = await adminDb.collection(COLLECTION).doc(reportId).get();
  if (!snap.exists) return null;
  return toUserReport(snap.id, snap.data() ?? {});
}

export class ReportReviewError extends Error {}

export async function reviewReport(params: {
  reportId: string;
  decision: 'reviewed' | 'dismissed';
  reviewerUid: string;
  reviewerEmail?: string | null;
}): Promise<void> {
  const { reportId, decision, reviewerUid, reviewerEmail } = params;
  const ref = adminDb.collection(COLLECTION).doc(reportId);

  const snap = await ref.get();
  if (!snap.exists) {
    throw new ReportReviewError('Report not found.');
  }

  const data = snap.data() ?? {};
  const currentStatus = (data.status as ReportStatus) ?? 'pending';
  if (currentStatus !== 'pending') {
    throw new ReportReviewError('This report has already been reviewed.');
  }

  await ref.update({
    status: decision,
    reviewedAtMs: Date.now(),
    reviewedBy: reviewerUid,
  });

  await recordAuditLog({
    actorUid: reviewerUid,
    actorEmail: reviewerEmail,
    action: `report.${decision === 'reviewed' ? 'review' : 'dismiss'}`,
    targetType: 'report',
    targetId: reportId,
    summary: `Marked report against ${data.targetUserId ?? 'unknown user'} as ${decision} (reason: ${data.reason ?? 'unspecified'})`,
  });
}

/**
 * Bulk version of reviewReport for clearing a backlog of pending reports
 * at once. Silently skips any id that's missing or already reviewed
 * (same guard as the single-item path) rather than failing the whole
 * batch -- the caller only ever selects what the current pending view
 * showed them, so a skip means it changed status between page load and
 * submit, not a bug. One audit log entry covers the whole batch instead
 * of one per report, since a reviewer chose one decision for all of them
 * together.
 */
export async function bulkReviewReports(params: {
  reportIds: string[];
  decision: 'reviewed' | 'dismissed';
  reviewerUid: string;
  reviewerEmail?: string | null;
}): Promise<{ updated: number; skipped: number }> {
  const { reportIds, decision, reviewerUid, reviewerEmail } = params;

  if (reportIds.length === 0) {
    throw new ReportReviewError('No reports selected.');
  }
  if (reportIds.length > 100) {
    throw new ReportReviewError('Select at most 100 reports at a time.');
  }

  const refs = reportIds.map((id) => adminDb.collection(COLLECTION).doc(id));
  const snaps = await adminDb.getAll(...refs);

  const nowMs = Date.now();
  const batch = adminDb.batch();
  let updated = 0;
  let skipped = 0;

  for (const snap of snaps) {
    const status = snap.exists ? ((snap.data()?.status as ReportStatus) ?? 'pending') : null;
    if (!snap.exists || status !== 'pending') {
      skipped += 1;
      continue;
    }
    batch.update(snap.ref, { status: decision, reviewedAtMs: nowMs, reviewedBy: reviewerUid });
    updated += 1;
  }

  if (updated > 0) {
    await batch.commit();
  }

  await recordAuditLog({
    actorUid: reviewerUid,
    actorEmail: reviewerEmail,
    action: `report.bulk_${decision === 'reviewed' ? 'review' : 'dismiss'}`,
    targetType: 'report',
    targetId: reportIds.join(','),
    summary: `Bulk marked ${updated} report(s) as ${decision}${
      skipped > 0 ? ` (${skipped} skipped — already reviewed or not found)` : ''
    }`,
  });

  return { updated, skipped };
}
