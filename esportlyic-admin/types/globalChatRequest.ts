// types/globalChatRequest.ts
//
// Mirrors globalChatRequests/{uid} as written by global_chat_screen.dart's
// _joinGlobalChat() (and joinGlobalChatWeb on web). The doc ID IS the user's
// uid — there's no separate requestId.
//
// Since 2026-11-22 there is no approval step: users set their own doc to
// 'approved' when they tap Join. 'pending' only remains on requests made
// before then. 'rejected' means an admin removed the user; firestore.rules
// stops the user from changing it, so only an admin can restore them.

export type GlobalChatRequestStatus = 'pending' | 'approved' | 'rejected';

export interface GlobalChatRequest {
  uid: string;
  userId: string;
  userName: string;
  userPhoto: string;
  status: GlobalChatRequestStatus;
  createdAtMs: number;
  updatedAtMs: number;
  joinedAtMs: number;
}

/**
 * Default tab on the Global Chat page. Users join themselves (no approval
 * since 2026-11-22), so the useful default is the member list; 'pending'
 * only holds older requests.
 */
export const DEFAULT_GLOBAL_CHAT_TAB: GlobalChatRequestStatus = 'approved';

/** Status changes an admin may make, by current status. */
export const GLOBAL_CHAT_ADMIN_TRANSITIONS: Record<
  GlobalChatRequestStatus,
  ReadonlyArray<'approved' | 'rejected'>
> = {
  pending: ['approved', 'rejected'],
  approved: ['rejected'],
  rejected: ['approved'],
};

/** Audit verb for an admin status change. */
export function globalChatAdminActionVerb(
  from: GlobalChatRequestStatus,
  to: 'approved' | 'rejected',
): 'approve' | 'reject' | 'remove' | 'restore' {
  if (from === 'pending') return to === 'approved' ? 'approve' : 'reject';
  return to === 'rejected' ? 'remove' : 'restore';
}
