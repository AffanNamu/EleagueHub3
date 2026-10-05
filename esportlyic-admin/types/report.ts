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

// Mirrors ReportTargetType in user_report.dart / sessionOptions-style
// client helpers. 'profile' (the original, and the default when the field
// is absent on legacy docs) means targetUserId IS the reported profile;
// 'message'/'post'/'comment' mean targetUserId is that content's author,
// and contextId/contextLocation locate the specific item.
export const REPORT_TARGET_TYPES = ['profile', 'message', 'post', 'comment'] as const;
export type ReportTargetType = (typeof REPORT_TARGET_TYPES)[number];

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
  /** Absent on legacy docs written before this field existed -- treat as 'profile'. */
  targetType?: ReportTargetType;
  /** The reported message/post/comment's own id. Empty for 'profile' reports. */
  contextId?: string;
  /** Extra locator for contextId -- a leagueId/masterLeagueId for a chat message, or a postId for a comment's parent post. Empty for 'profile'/'post' reports. */
  contextLocation?: string;
}
