// lib/masterLeagues/verificationRequestsRepository.ts
//
// Mirrors lib/features/master_leagues/domain/organizer_verification_request.dart
// (the OrganizerVerificationRequest model) and
// lib/features/admin/organizer_verification_requests_screen.dart's
// _reviewRequest() transaction — the admin-only review flow for
// master_league_verification_requests. Approve extends/starts the 90-day
// verification window on master_leagues/{id} (differentiating 'initial' vs
// 'renewal' requests), optionally propagates the submitted logo, marks the
// owner's users/{uid} doc, and fires a non-fatal organizer_feed event.

import { collection, doc, onSnapshot, orderBy, query, runTransaction, where, limit as fsLimit } from 'firebase/firestore';
import { useEffect, useState } from 'react';
import { db } from '@/lib/firebase';
import { addVerificationApprovedEvent } from '@/lib/masterLeagues/organizerFeedRepository';

export type VerificationReviewAction = 'approve' | 'reject' | 'info_requested';

export interface OrganizerVerificationRequest {
  requestId: string;
  masterLeagueId: string;
  ownerId: string;
  status: string;
  requestType: string;
  provider: string;
  receiptId: string;
  paymentId: string;
  attemptId: string;
  submittedAtMs: number;
  reviewedAtMs: number;
  reviewedBy: string;
  note: string;
  resubmittedAtMs: number;
  orgName: string;
  orgType: string;
  orgCountry: string;
  orgRegion: string;
  orgCity: string;
  contactEmail: string;
  contactPhone: string;
  website: string;
  socialLink: string;
  applicantFullName: string;
  applicantRole: string;
  orgDescription: string;
  competitionTypes: string;
  verificationReason: string;
  supportingLinks: string;
  logoUrl: string;
}

function asStr(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

function asInt(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : 0;
}

export function verificationRequestFromDoc(id: string, data: Record<string, unknown>): OrganizerVerificationRequest {
  return {
    requestId: asStr(data.requestId) || id,
    masterLeagueId: asStr(data.masterLeagueId),
    ownerId: asStr(data.ownerId),
    status: asStr(data.status) || 'pending',
    requestType: asStr(data.requestType) || 'initial',
    provider: asStr(data.provider),
    receiptId: asStr(data.receiptId),
    paymentId: asStr(data.paymentId),
    attemptId: asStr(data.attemptId),
    submittedAtMs: asInt(data.submittedAtMs),
    reviewedAtMs: asInt(data.reviewedAtMs),
    reviewedBy: asStr(data.reviewedBy),
    note: asStr(data.note),
    resubmittedAtMs: asInt(data.resubmittedAtMs),
    orgName: asStr(data.orgName),
    orgType: asStr(data.orgType),
    orgCountry: asStr(data.orgCountry),
    orgRegion: asStr(data.orgRegion),
    orgCity: asStr(data.orgCity),
    contactEmail: asStr(data.contactEmail),
    contactPhone: asStr(data.contactPhone),
    website: asStr(data.website),
    socialLink: asStr(data.socialLink),
    applicantFullName: asStr(data.applicantFullName),
    applicantRole: asStr(data.applicantRole),
    orgDescription: asStr(data.orgDescription),
    competitionTypes: asStr(data.competitionTypes),
    verificationReason: asStr(data.verificationReason),
    supportingLinks: asStr(data.supportingLinks),
    logoUrl: asStr(data.logoUrl),
  };
}

export function isLegacyPaymentOnly(req: OrganizerVerificationRequest): boolean {
  return req.orgName.trim().length === 0 && req.applicantFullName.trim().length === 0;
}

// ── Real-time list, filtered by status (newest first) ───────────────────

export function useVerificationRequests(status: string) {
  const [requests, setRequests] = useState<OrganizerVerificationRequest[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const loadingTimer = setTimeout(() => setLoading(true), 0);
    const q = query(
      collection(db, 'master_league_verification_requests'),
      where('status', '==', status),
      orderBy('submittedAtMs', 'desc'),
      fsLimit(100),
    );
    const unsub = onSnapshot(
      q,
      (snap) => {
        setRequests(snap.docs.map((d) => verificationRequestFromDoc(d.id, d.data())));
        setLoading(false);
      },
      (err) => {
        console.warn('[verificationRequestsRepository] watch failed:', err);
        setRequests([]);
        setLoading(false);
      },
    );
    return () => {
      clearTimeout(loadingTimer);
      unsub();
    };
  }, [status]);

  return { requests, loading };
}

// ── Review a request (approve / reject / request more info) ─────────────

export async function reviewVerificationRequestWeb({
  request, action, adminUid, note,
}: {
  request: OrganizerVerificationRequest;
  action: VerificationReviewAction;
  adminUid: string;
  note: string;
}): Promise<{ approvedRenewal: boolean }> {
  const requestRef = doc(db, 'master_league_verification_requests', request.requestId);
  const mlRef = doc(db, 'master_leagues', request.masterLeagueId);
  const now = Date.now();
  let approvedRenewal = false;

  await runTransaction(db, async (txn) => {
    const requestSnap = await txn.get(requestRef);
    if (!requestSnap.exists()) throw new Error('Verification request not found.');

    const requestData = requestSnap.data() as Record<string, unknown>;
    const status = asStr(requestData.status).toLowerCase();
    if (status !== 'pending' && status !== 'info_requested') {
      throw new Error('Only pending requests can be reviewed.');
    }

    const requestType = (asStr(requestData.requestType) || 'initial').toLowerCase();
    const logoUrl = asStr(requestData.logoUrl);

    const mlSnap = await txn.get(mlRef);
    if (!mlSnap.exists()) throw new Error('Master League not found.');

    const mlData = mlSnap.data() as Record<string, unknown>;
    const currentExpiry = asInt(mlData.verificationExpiresAtMs);
    const currentLogoUrl = asStr(mlData.logoUrl);

    const newRequestStatus = action === 'approve' ? 'approved' : action === 'reject' ? 'rejected' : 'info_requested';

    txn.update(requestRef, {
      status: newRequestStatus,
      reviewedAtMs: now,
      reviewedBy: adminUid,
      note,
    });

    if (action === 'info_requested') {
      txn.update(mlRef, {
        verificationStatus: 'info_requested',
        verifiedBadge: false,
        verificationReviewedBy: adminUid,
        verificationNote: note,
        verificationRequestType: requestType,
        updatedAtMs: now,
      });
      return;
    }

    const approve = action === 'approve';
    const durationMs = 90 * 24 * 60 * 60 * 1000;
    let nextExpiryMs = currentExpiry;
    if (approve) {
      if (requestType === 'renewal') {
        approvedRenewal = true;
        const base = currentExpiry > now ? currentExpiry : now;
        nextExpiryMs = base + durationMs;
      } else {
        nextExpiryMs = now + durationMs;
      }
    }

    const mlUpdate: Record<string, unknown> = {
      verificationStatus: newRequestStatus,
      verifiedBadge: approve,
      verificationApprovedAtMs: approve ? now : 0,
      verificationExpiresAtMs: approve ? nextExpiryMs : currentExpiry,
      verificationReviewedBy: adminUid,
      verificationNote: note,
      verificationRequestType: requestType,
      updatedAtMs: now,
    };

    // Propagate the approved logo as the organizer's official identity,
    // but never overwrite a logo the owner already set.
    if (approve && logoUrl.length > 0 && currentLogoUrl.length === 0) {
      mlUpdate.logoUrl = logoUrl;
    }

    txn.update(mlRef, mlUpdate);

    if (approve) {
      const userRef = doc(db, 'users', request.ownerId);
      txn.set(userRef, { lastVerifiedMasterLeagueId: request.masterLeagueId, updatedAt: now }, { merge: true });
    }
  });

  if (action === 'approve') {
    try {
      await addVerificationApprovedEvent({
        masterLeagueId: request.masterLeagueId,
        actorId: adminUid,
        actorName: 'Admin',
        isRenewal: approvedRenewal,
      });
    } catch (e) {
      console.warn('[verificationRequestsRepository] addVerificationApprovedEvent failed (non-fatal):', e);
    }
  }

  return { approvedRenewal };
}
