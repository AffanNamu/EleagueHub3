// types/content.ts
//
// Mirrors public_posts/{postId} and its comments subcollection exactly
// as validated in firestore.rules AND cross-checked against
// public_post.dart directly. Correction from the prior version: added
// matchScoreHome/matchScoreAway/matchOpponentName, which are only
// meaningful for postType === 'match_result' but always present on the
// document (defaulting to 0/0/'').

export type PostType = 'text' | 'competition_promo' | 'match_result';

export interface PublicPost {
  postId: string;
  authorId: string;
  authorDisplayName: string;
  authorPhotoUrl: string;
  createdAtMs: number;
  text: string;
  mediaUrl: string;
  audioUrl: string;
  postType: PostType;
  leagueId: string;
  leagueName: string;
  matchScoreHome: number;
  matchScoreAway: number;
  matchOpponentName: string;
  isPromoted: boolean;
  likeCount: number;
  commentCount: number;
  deleted: boolean;
}

export interface PostComment {
  commentId: string;
  postId: string;
  authorId: string;
  authorDisplayName: string;
  authorPhotoUrl: string;
  text: string;
  createdAtMs: number;
  deleted: boolean;
}
