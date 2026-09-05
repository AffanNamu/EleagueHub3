// types/discussion.ts
//
// Mirrors discussion_threads/{threadId} and its replies subcollection
// exactly as validated in firestore.rules.

export interface DiscussionThread {
  threadId: string;
  authorId: string;
  authorDisplayName: string;
  authorPhotoUrl: string;
  title: string;
  body: string;
  createdAtMs: number;
  lastReplyAtMs: number;
  replyCount: number;
  deleted: boolean;
}

export interface DiscussionReply {
  replyId: string;
  threadId: string;
  authorId: string;
  authorDisplayName: string;
  authorPhotoUrl: string;
  text: string;
  createdAtMs: number;
  deleted: boolean;
}
