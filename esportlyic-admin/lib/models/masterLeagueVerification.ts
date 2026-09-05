// lib/models/masterLeagueVerification.ts
//
// Shared, isomorphic (client + server safe) helpers for verification
// requests — status labels and the legacy-request detection ported
// directly from OrganizerVerificationRequest.isLegacyPaymentOnly in
// the Flutter app.

import type { VerificationRequest, VerificationStatus } from '@/types/verification';

export function isLegacyPaymentOnly(request: VerificationRequest): boolean {
  return request.orgName.trim().length === 0 && request.applicantFullName.trim().length === 0;
}

export function verificationStatusLabel(status: VerificationStatus): string {
  switch (status) {
    case 'pending':
      return 'Pending Review';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    case 'info_requested':
      return 'Info Requested';
    default:
      return status;
  }
}

export function verificationStatusTone(
  status: VerificationStatus,
): 'brand' | 'success' | 'warning' | 'danger' | 'info' {
  switch (status) {
    case 'pending':
      return 'warning';
    case 'approved':
      return 'success';
    case 'rejected':
      return 'danger';
    case 'info_requested':
      return 'info';
    default:
      return 'brand';
  }
}

export function requestTypeLabel(type: string): string {
  return type === 'renewal' ? 'Renewal' : 'Initial Application';
}
