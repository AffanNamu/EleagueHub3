// types/moderationCase.ts
//
// NEW — no mobile-side equivalent exists; this is a purely admin-side
// investigation tool, matching the "Moderation Case ID" concept
// described in the company dashboard vision. Groups existing evidence
// (reports, content, chat requests) rather than duplicating it.

export type CaseStatus = 'open' | 'investigating' | 'resolved' | 'dismissed' | 'appealed';

export interface CaseNote {
  authorUid: string;
  authorName: string;
  text: string;
  createdAtMs: number;
}

export interface LinkedEvidence {
  type: 'report' | 'post' | 'comment' | 'discussion_thread' | 'global_chat_request';
  id: string;
  label: string;
}

export interface ModerationCase {
  caseId: string;
  targetUserId: string;
  targetUserName: string;
  reason: string;
  status: CaseStatus;
  openedBy: string;
  openedByName: string;
  openedAtMs: number;
  linkedEvidence: LinkedEvidence[];
  notes: CaseNote[];
  decision: string;
  actionTaken: string;
  resolvedAtMs: number;
  resolvedBy: string;
}
