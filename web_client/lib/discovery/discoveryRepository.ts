import { collection, doc, setDoc, updateDoc, getDoc, runTransaction } from 'firebase/firestore';
import { db } from '@/lib/firebase';

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

export async function createDiscussionThreadWeb({
  authorId, authorDisplayName, authorPhotoUrl, title, body
}: {
  authorId: string; authorDisplayName: string; authorPhotoUrl: string; title: string; body: string;
}) {
  const ref = doc(collection(db, 'discussion_threads'));
  const now = Date.now();

  await setDoc(ref, {
    threadId: ref.id,
    authorId,
    authorDisplayName: authorDisplayName.trim(),
    authorPhotoUrl: authorPhotoUrl.trim(),
    title: title.trim().substring(0, 140),
    body: body.trim().substring(0, 4000),
    createdAtMs: now,
    lastReplyAtMs: now,
    replyCount: 0,
    deleted: false,
  });
}

export async function createDiscussionReplyWeb({
  threadId, authorId, authorDisplayName, authorPhotoUrl, text
}: {
  threadId: string; authorId: string; authorDisplayName: string; authorPhotoUrl: string; text: string;
}) {
  const threadRef = doc(db, 'discussion_threads', threadId);
  const replyRef = doc(collection(threadRef, 'replies'));
  const now = Date.now();

  await runTransaction(db, async (txn) => {
    const threadSnap = await txn.get(threadRef);
    if (!threadSnap.exists()) throw new Error('This discussion no longer exists.');
    
    const currentCount = threadSnap.data().replyCount || 0;

    txn.set(replyRef, {
      replyId: replyRef.id,
      threadId,
      authorId,
      authorDisplayName: authorDisplayName.trim(),
      authorPhotoUrl: authorPhotoUrl.trim(),
      text: text.trim().substring(0, 2000),
      createdAtMs: now,
      deleted: false,
    });

    txn.update(threadRef, {
      replyCount: currentCount + 1,
      lastReplyAtMs: now,
    });
  });
}

export async function deleteDiscussionThreadWeb(threadId: string, authUid: string) {
  const ref = doc(db, 'discussion_threads', threadId);
  const snap = await getDoc(ref);
  if (!snap.exists()) return;
  if (snap.data().authorId !== authUid) throw new Error('You can only delete your own discussion.');
  await updateDoc(ref, { deleted: true });
}

export async function deleteDiscussionReplyWeb(threadId: string, replyId: string, authUid: string) {
  const ref = doc(db, 'discussion_threads', threadId, 'replies', replyId);
  const snap = await getDoc(ref);
  if (!snap.exists()) return;
  if (snap.data().authorId !== authUid) throw new Error('You can only delete your own reply.');
  await updateDoc(ref, { deleted: true });
}
