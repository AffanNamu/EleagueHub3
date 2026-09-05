// types/globalChatRequest.ts
//
// Mirrors globalChatRequests/{uid} exactly as created in
// global_chat_screen.dart's _requestAccess(). Note the doc ID IS the
// requesting user's uid — there's no separate requestId.

export type GlobalChatRequestStatus = 'pending' | 'approved' | 'rejected';

export interface GlobalChatRequest {
  uid: string;
  userId: string;
  userName: string;
  userPhoto: string;
  status: GlobalChatRequestStatus;
  createdAtMs: number;
  updatedAtMs: number;
}
