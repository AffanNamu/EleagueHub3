// lib/repositories/contentAdminRepository.ts

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { PostComment, PostType, PublicPost } from '@/types/content';

function toPost(id: string, data: FirebaseFirestore.DocumentData): PublicPost {
  return {
    postId: id,
    authorId: data.authorId ?? '',
    authorDisplayName: data.authorDisplayName ?? '',
    authorPhotoUrl: data.authorPhotoUrl ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    text: data.text ?? '',
    mediaUrl: data.mediaUrl ?? '',
    audioUrl: data.audioUrl ?? '',
    postType: (data.postType as PostType) ?? 'text',
    leagueId: data.leagueId ?? '',
    leagueName: data.leagueName ?? '',
    matchScoreHome: typeof data.matchScoreHome === 'number' ? data.matchScoreHome : 0,
    matchScoreAway: typeof data.matchScoreAway === 'number' ? data.matchScoreAway : 0,
    matchOpponentName: data.matchOpponentName ?? '',
    isPromoted: data.isPromoted === true,
    likeCount: typeof data.likeCount === 'number' ? data.likeCount : 0,
    commentCount: typeof data.commentCount === 'number' ? data.commentCount : 0,
    deleted: data.deleted === true,
  };
}

function toComment(id: string, data: FirebaseFirestore.DocumentData): PostComment {
  return {
    commentId: id,
    postId: data.postId ?? '',
    authorId: data.authorId ?? '',
    authorDisplayName: data.authorDisplayName ?? '',
    authorPhotoUrl: data.authorPhotoUrl ?? '',
    text: data.text ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    deleted: data.deleted === true,
  };
}

export async function listPosts(params: { includeDeleted?: boolean; limit?: number } = {}): Promise<PublicPost[]> {
  const { includeDeleted = false, limit = 50 } = params;

  let query: FirebaseFirestore.Query = adminDb.collection('public_posts').orderBy('createdAtMs', 'desc');
  if (!includeDeleted) {
    query = query.where('deleted', '==', false);
  }

  const snap = await query.limit(limit).get();
  return snap.docs.map((doc) => toPost(doc.id, doc.data()));
}

export async function getPost(postId: string): Promise<PublicPost | null> {
  const snap = await adminDb.collection('public_posts').doc(postId).get();
  if (!snap.exists) return null;
  return toPost(snap.id, snap.data() ?? {});
}

export async function listComments(postId: string): Promise<PostComment[]> {
  const snap = await adminDb
    .collection('public_posts')
    .doc(postId)
    .collection('comments')
    .orderBy('createdAtMs', 'asc')
    .get();
  return snap.docs.map((doc) => toComment(doc.id, doc.data()));
}

export class ContentModerationError extends Error {}

export async function softDeletePost(params: {
  postId: string;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection('public_posts').doc(params.postId);
  const snap = await ref.get();

  if (!snap.exists) throw new ContentModerationError('Post not found.');
  if (snap.data()?.deleted === true) throw new ContentModerationError('Post is already removed.');

  await ref.update({ deleted: true });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'content.post.remove',
    targetType: 'public_post',
    targetId: params.postId,
    summary: `Removed post by ${snap.data()?.authorDisplayName ?? snap.data()?.authorId ?? 'unknown'}`,
  });
}

export async function softDeleteComment(params: {
  postId: string;
  commentId: string;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection('public_posts').doc(params.postId).collection('comments').doc(params.commentId);
  const snap = await ref.get();

  if (!snap.exists) throw new ContentModerationError('Comment not found.');
  if (snap.data()?.deleted === true) throw new ContentModerationError('Comment is already removed.');

  await ref.update({ deleted: true });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'content.comment.remove',
    targetType: 'post_comment',
    targetId: `${params.postId}/${params.commentId}`,
    summary: `Removed comment by ${snap.data()?.authorDisplayName ?? snap.data()?.authorId ?? 'unknown'} on post ${params.postId}`,
  });
}
