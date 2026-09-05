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
