// lib/repositories/discussionsAdminRepository.ts
//
// Same soft-delete pattern as contentAdminRepository.ts — setting
// deleted: true rather than a hard delete, consistent with how the rest
// of the platform treats content removal.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { DiscussionReply, DiscussionThread } from '@/types/discussion';

function toThread(id: string, data: FirebaseFirestore.DocumentData): DiscussionThread {
  return {
    threadId: id,
    authorId: data.authorId ?? '',
    authorDisplayName: data.authorDisplayName ?? '',
    authorPhotoUrl: data.authorPhotoUrl ?? '',
    title: data.title ?? '',
    body: data.body ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    lastReplyAtMs: typeof data.lastReplyAtMs === 'number' ? data.lastReplyAtMs : 0,
    replyCount: typeof data.replyCount === 'number' ? data.replyCount : 0,
    deleted: data.deleted === true,
  };
}

function toReply(id: string, data: FirebaseFirestore.DocumentData): DiscussionReply {
  return {
    replyId: id,
    threadId: data.threadId ?? '',
    authorId: data.authorId ?? '',
    authorDisplayName: data.authorDisplayName ?? '',
    authorPhotoUrl: data.authorPhotoUrl ?? '',
    text: data.text ?? '',
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    deleted: data.deleted === true,
  };
}

export async function listDiscussionThreads(params: { limit?: number } = {}): Promise<DiscussionThread[]> {
  const { limit = 50 } = params;
  const snap = await adminDb
    .collection('discussion_threads')
    .where('deleted', '==', false)
    .orderBy('lastReplyAtMs', 'desc')
    .limit(limit)
    .get();
  return snap.docs.map((doc) => toThread(doc.id, doc.data()));
}

export async function getDiscussionThread(threadId: string): Promise<DiscussionThread | null> {
  const snap = await adminDb.collection('discussion_threads').doc(threadId).get();
  if (!snap.exists) return null;
  return toThread(snap.id, snap.data() ?? {});
}

export async function listDiscussionReplies(threadId: string): Promise<DiscussionReply[]> {
  const snap = await adminDb
    .collection('discussion_threads')
    .doc(threadId)
    .collection('replies')
    .orderBy('createdAtMs', 'asc')
    .get();
  return snap.docs.map((doc) => toReply(doc.id, doc.data()));
}

export class DiscussionModerationError extends Error {}

export async function softDeleteThread(params: {
  threadId: string;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection('discussion_threads').doc(params.threadId);
  const snap = await ref.get();

  if (!snap.exists) throw new DiscussionModerationError('Thread not found.');
  if (snap.data()?.deleted === true) throw new DiscussionModerationError('Thread is already removed.');

  await ref.update({ deleted: true });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'content.discussion.remove',
    targetType: 'discussion_thread',
    targetId: params.threadId,
    summary: `Removed discussion thread "${snap.data()?.title ?? params.threadId}" by ${snap.data()?.authorDisplayName ?? 'unknown'}`,
  });
}

export async function softDeleteReply(params: {
  threadId: string;
  replyId: string;
  actorUid: string;
  actorEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection('discussion_threads').doc(params.threadId).collection('replies').doc(params.replyId);
  const snap = await ref.get();

  if (!snap.exists) throw new DiscussionModerationError('Reply not found.');
  if (snap.data()?.deleted === true) throw new DiscussionModerationError('Reply is already removed.');

  await ref.update({ deleted: true });

  await recordAuditLog({
    actorUid: params.actorUid,
    actorEmail: params.actorEmail,
    action: 'content.discussion_reply.remove',
    targetType: 'discussion_reply',
    targetId: `${params.threadId}/${params.replyId}`,
    summary: `Removed reply by ${snap.data()?.authorDisplayName ?? 'unknown'} on thread ${params.threadId}`,
  });
}
