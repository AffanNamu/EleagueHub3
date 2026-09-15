// lib/repositories/globalChatRequestsAdminRepository.ts

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { GlobalChatRequest, GlobalChatRequestStatus } from '@/types/globalChatRequest';

const COLLECTION = 'globalChatRequests';

function toRequest(uid: string, data: FirebaseFirestore.DocumentData): GlobalChatRequest {
  return {
    uid,
    userId: data.userId ?? uid,
    userName: data.userName ?? '',
    userPhoto: data.userPhoto ?? '',
    status: (data.status as GlobalChatRequestStatus) ?? 'pending',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
  };
}

export async function listGlobalChatRequests(
  statusFilter?: GlobalChatRequestStatus,
): Promise<GlobalChatRequest[]> {
  let query: FirebaseFirestore.Query = adminDb.collection(COLLECTION);
  if (statusFilter) query = query.where('status', '==', statusFilter);
  const snap = await query.orderBy('createdAtMs', 'desc').limit(100).get();
  return snap.docs.map((doc) => toRequest(doc.id, doc.data()));
}

export class GlobalChatRequestReviewError extends Error {}

export async function reviewGlobalChatRequest(params: {
  uid: string;
  decision: 'approved' | 'rejected';
  reviewerUid: string;
  reviewerEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection(COLLECTION).doc(params.uid);
  const snap = await ref.get();

  if (!snap.exists) {
    throw new GlobalChatRequestReviewError('Request not found.');
  }

  const data = snap.data() ?? {};
  const currentStatus = (data.status as string) ?? 'pending';
  if (currentStatus !== 'pending') {
    throw new GlobalChatRequestReviewError('This request has already been decided.');
  }

  await ref.update({
    status: params.decision,
    updatedAtMs: Date.now(),
  });

  await recordAuditLog({
    actorUid: params.reviewerUid,
    actorEmail: params.reviewerEmail,
    action: `global_chat_request.${params.decision === 'approved' ? 'approve' : 'reject'}`,
    targetType: 'global_chat_request',
    targetId: params.uid,
    summary: `${params.decision === 'approved' ? 'Approved' : 'Rejected'} Global Chat access for ${data.userName || params.uid}`,
  });
}

/**
 * Bulk version of reviewGlobalChatRequest for clearing a backlog of
 * pending access requests at once. Skips any uid that's missing or
 * already decided rather than failing the whole batch.
 */
export async function bulkReviewGlobalChatRequests(params: {
  uids: string[];
  decision: 'approved' | 'rejected';
  reviewerUid: string;
  reviewerEmail?: string | null;
}): Promise<{ updated: number; skipped: number }> {
  const { uids, decision, reviewerUid, reviewerEmail } = params;

  if (uids.length === 0) {
    throw new GlobalChatRequestReviewError('No requests selected.');
  }
  if (uids.length > 100) {
    throw new GlobalChatRequestReviewError('Select at most 100 requests at a time.');
  }

  const refs = uids.map((uid) => adminDb.collection(COLLECTION).doc(uid));
  const snaps = await adminDb.getAll(...refs);

  const nowMs = Date.now();
  const batch = adminDb.batch();
  let updated = 0;
  let skipped = 0;

  for (const snap of snaps) {
    const status = snap.exists ? ((snap.data()?.status as string) ?? 'pending') : null;
    if (!snap.exists || status !== 'pending') {
      skipped += 1;
      continue;
    }
    batch.update(snap.ref, { status: decision, updatedAtMs: nowMs });
    updated += 1;
  }

  if (updated > 0) {
    await batch.commit();
  }

  await recordAuditLog({
    actorUid: reviewerUid,
    actorEmail: reviewerEmail,
    action: `global_chat_request.bulk_${decision === 'approved' ? 'approve' : 'reject'}`,
    targetType: 'global_chat_request',
    targetId: uids.join(','),
    summary: `Bulk ${decision === 'approved' ? 'approved' : 'rejected'} Global Chat access for ${updated} user(s)${
      skipped > 0 ? ` (${skipped} skipped — already decided or not found)` : ''
    }`,
  });

  return { updated, skipped };
}
