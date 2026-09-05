// types/report.ts
//
// Mirrors UserReportReason and the reports/{reportId} document shape
// exactly as confirmed in user_report.dart / report_repository.dart /
// firestore.rules. No "note" field exists in this schema — admin review
// can only set status + reviewedBy + reviewedAtMs, nothing free-text.

export const REPORT_REASONS = ['spam', 'harassment', 'impersonation', 'cheating', 'other'] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

export function reportReasonLabel(reason: string): string {
  switch (reason) {
    case 'spam':
      return 'Spam';
    case 'harassment':
      return 'Harassment';
    case 'impersonation':
      return 'Impersonation';
    case 'cheating':
      return 'Cheating';
    case 'other':
    default:
      return 'Other';
  }
}

export type ReportStatus = 'pending' | 'reviewed' | 'dismissed';

export interface UserReport {
  reportId: string;
  reporterId: string;
  targetUserId: string;
  reason: ReportReason;
  details: string;
  status: ReportStatus;
  createdAtMs: number;
  reviewedAtMs: number;
  reviewedBy: string;
}
