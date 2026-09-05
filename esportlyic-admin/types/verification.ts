// types/verification.ts
//
// Client-safe types for the Verification module. Mirrors
// OrganizerVerificationRequest from the Flutter app exactly — field names
// match 1:1 with master_league_verification_requests/{requestId}.

export type VerificationStatus = 'pending' | 'approved' | 'rejected' | 'info_requested';

export type VerificationRequestType = 'initial' | 'renewal';

export interface VerificationRequest {
  requestId: string;
  masterLeagueId: string;
  ownerId: string;
  status: VerificationStatus;
  requestType: VerificationRequestType;

  provider: string;
  receiptId: string;
  paymentId: string;
  attemptId: string;

  submittedAtMs: number;
  reviewedAtMs: number;
  reviewedBy: string;
  note: string;
  resubmittedAtMs: number | null;

  // Application form fields — empty on legacy (payment-only) requests
  // submitted before the application form existed.
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
  competitionTypes: string[];
  verificationReason: string;
  supportingLinks: string[];
  logoUrl: string;
}

export interface MasterLeagueSummary {
  id: string;
  name: string;
  ownerId: string;
  plan: 'basic' | 'pro' | 'elite';
  logoUrl: string;
  bannerUrl: string;
  verificationStatus: VerificationStatus | 'none';
  verifiedBadge: boolean;
  verificationExpiresAtMs: number;
  totalTournamentsCreated: number;
  totalParticipantsTeams: number;
  followersCount: number;
}

export interface OwnerProfileSummary {
  userId: string;
  displayName: string;
  photoUrl: string;
}

export type ReviewAction = 'approve' | 'reject' | 'request_info';
