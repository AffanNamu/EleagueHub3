// lib/repositories/verificationAdminRepository.ts
//
// Server-only repository for master_league_verification_requests.
//
// reviewVerificationRequest() is a byte-for-byte port of the transaction
// in organizer_verification_requests_screen.dart's _reviewRequest — same
// guards, same 90-day hardcoded duration, same renewal-extends-from-
// max(expiry,now) logic, same early-return shape for info_requested, same
// full field set on reject. Runs through the Admin SDK. Now also records
// every decision to audit_logs after the transaction commits.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { ReviewAction, VerificationRequest, VerificationStatus } from '@/types/verification';

const REQUESTS_COLLECTION = 'master_league_verification_requests';
const MASTER_LEAGUES_COLLECTION = 'master_leagues';
const USERS_COLLECTION = 'users';

const VERIFICATION_DURATION_MS = 90 * 24 * 60 * 60 * 1000;

function toVerificationRequest(id: string, data: FirebaseFirestore.DocumentData): VerificationRequest {
  return {
    requestId: id,
    masterLeagueId: data.masterLeagueId ?? '',
    ownerId: data.ownerId ?? '',
    status: (data.status as VerificationStatus) ?? 'pending',
    requestType: data.requestType === 'renewal' ? 'renewal' : 'initial',
    provider: data.provider ?? '',
    receiptId: data.receiptId ?? '',
    paymentId: data.paymentId ?? '',
    attemptId: data.attemptId ?? '',
    submittedAtMs: typeof data.submittedAtMs === 'number' ? data.submittedAtMs : 0,
    reviewedAtMs: typeof data.reviewedAtMs === 'number' ? data.reviewedAtMs : 0,
    reviewedBy: data.reviewedBy ?? '',
    note: data.note ?? '',
    resubmittedAtMs: typeof data.resubmittedAtMs === 'number' ? data.resubmittedAtMs : null,
    orgName: data.orgName ?? '',
    orgType: data.orgType ?? '',
    orgCountry: data.orgCountry ?? '',
    orgRegion: data.orgRegion ?? '',
    orgCity: data.orgCity ?? '',
    contactEmail: data.contactEmail ?? '',
    contactPhone: data.contactPhone ?? '',
    website: data.website ?? '',
    socialLink: data.socialLink ?? '',
    applicantFullName: data.applicantFullName ?? '',
    applicantRole: data.applicantRole ?? '',
    orgDescription: data.orgDescription ?? '',
    competitionTypes: Array.isArray(data.competitionTypes) ? data.competitionTypes : [],
    verificationReason: data.verificationReason ?? '',
    supportingLinks: Array.isArray(data.supportingLinks) ? data.supportingLinks : [],
    logoUrl: data.logoUrl ?? '',
  };
}

export async function listVerificationRequests(
  statusFilter?: VerificationStatus,
): Promise<VerificationRequest[]> {
  let query: FirebaseFirestore.Query = adminDb.collection(REQUESTS_COLLECTION);
  if (statusFilter) query = query.where('status', '==', statusFilter);
  const snap = await query.orderBy('submittedAtMs', 'desc').limit(100).get();
  return snap.docs.map((doc) => toVerificationRequest(doc.id, doc.data()));
}

export async function getVerificationRequest(requestId: string): Promise<VerificationRequest | null> {
  const snap = await adminDb.collection(REQUESTS_COLLECTION).doc(requestId).get();
  if (!snap.exists) return null;
  return toVerificationRequest(snap.id, snap.data() ?? {});
}

export class VerificationReviewError extends Error {}

export async function reviewVerificationRequest(params: {
  requestId: string;
  action: ReviewAction;
  note: string;
  reviewerUid: string;
  reviewerEmail?: string | null;
}): Promise<{ approvedRenewal: boolean }> {
  const { requestId, action, note, reviewerUid, reviewerEmail } = params;

  if (action !== 'approve' && !note.trim()) {
    throw new VerificationReviewError('A note is required for reject and request-info actions.');
  }

  const nowMs = Date.now();
  let approvedRenewal = false;
  let orgNameForLog = '';
  let masterLeagueIdForLog = '';

  await adminDb.runTransaction(async (transaction) => {
    const requestRef = adminDb.collection(REQUESTS_COLLECTION).doc(requestId);
    const requestSnap = await transaction.get(requestRef);

    if (!requestSnap.exists) {
      throw new VerificationReviewError('Verification request not found.');
    }

    const requestData = requestSnap.data() ?? {};
    const currentStatus = ((requestData.status as string) ?? '').trim().toLowerCase();

    if (currentStatus !== 'pending' && currentStatus !== 'info_requested') {
      throw new VerificationReviewError('Only pending requests can be reviewed.');
    }

    const requestType = ((requestData.requestType as string) ?? 'initial').trim().toLowerCase();
    const logoUrl = ((requestData.logoUrl as string) ?? '').trim();
    const masterLeagueId = requestData.masterLeagueId as string;
    orgNameForLog = ((requestData.orgName as string) ?? '').trim();
    masterLeagueIdForLog = masterLeagueId;

    if (!masterLeagueId) {
      throw new VerificationReviewError('Request is missing a masterLeagueId.');
    }

    const masterLeagueRef = adminDb.collection(MASTER_LEAGUES_COLLECTION).doc(masterLeagueId);
    const masterLeagueSnap = await transaction.get(masterLeagueRef);

    if (!masterLeagueSnap.exists) {
      throw new VerificationReviewError('Master League not found.');
    }

    const masterLeagueData = masterLeagueSnap.data() ?? {};
    const currentExpiry = typeof masterLeagueData.verificationExpiresAtMs === 'number' ? masterLeagueData.verificationExpiresAtMs : 0;
    const currentLogoUrl = ((masterLeagueData.logoUrl as string) ?? '').trim();

    const newRequestStatus: VerificationStatus =
      action === 'approve' ? 'approved' : action === 'reject' ? 'rejected' : 'info_requested';

    transaction.update(requestRef, {
      status: newRequestStatus,
      reviewedAtMs: nowMs,
      reviewedBy: reviewerUid,
      note: note.trim(),
    });

    if (action === 'request_info') {
      transaction.update(masterLeagueRef, {
        verificationStatus: 'info_requested',
        verifiedBadge: false,
        verificationReviewedBy: reviewerUid,
        verificationNote: note.trim(),
        verificationRequestType: requestType,
        updatedAtMs: nowMs,
      });
      return;
    }

    const approve = action === 'approve';
    let nextExpiryMs = currentExpiry;

    if (approve) {
      if (requestType === 'renewal') {
        approvedRenewal = true;
        const base = currentExpiry > nowMs ? currentExpiry : nowMs;
        nextExpiryMs = base + VERIFICATION_DURATION_MS;
      } else {
        nextExpiryMs = nowMs + VERIFICATION_DURATION_MS;
      }
    }

    const masterLeagueUpdate: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
      verificationStatus: newRequestStatus,
      verifiedBadge: approve,
      verificationApprovedAtMs: approve ? nowMs : 0,
      verificationExpiresAtMs: approve ? nextExpiryMs : currentExpiry,
      verificationReviewedBy: reviewerUid,
      verificationNote: note.trim(),
      verificationRequestType: requestType,
      updatedAtMs: nowMs,
    };

    if (approve && logoUrl.length > 0 && currentLogoUrl.length === 0) {
      masterLeagueUpdate.logoUrl = logoUrl;
    }

    transaction.update(masterLeagueRef, masterLeagueUpdate);

    if (approve) {
      const ownerId = requestData.ownerId as string;
      if (ownerId) {
        const userRef = adminDb.collection(USERS_COLLECTION).doc(ownerId);
        transaction.set(
          userRef,
          { lastVerifiedMasterLeagueId: masterLeagueId, updatedAt: nowMs },
          { merge: true },
        );
      }
    }
  });

  await recordAuditLog({
    actorUid: reviewerUid,
    actorEmail: reviewerEmail,
    action: `verification.${action}`,
    targetType: 'verification_request',
    targetId: requestId,
    summary: orgNameForLog
      ? `${action === 'approve' ? 'Approved' : action === 'reject' ? 'Rejected' : 'Requested info for'} verification for "${orgNameForLog}" (${masterLeagueIdForLog})`
      : `${action === 'approve' ? 'Approved' : action === 'reject' ? 'Rejected' : 'Requested info for'} verification for workspace ${masterLeagueIdForLog}`,
  });

  // KNOWN GAP: the mobile screen also fires
  // OrganizerFeedFirebase.addVerificationApprovedEvent() after a
  // successful approve — still not replicated (organizer_feed_firebase.dart
  // not yet provided).

  return { approvedRenewal };
}
