import { collection, doc, setDoc, updateDoc, getDoc, query, orderBy, limit, onSnapshot, runTransaction } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface PublicPost {
  postId: string;
  authorId: string;
  authorDisplayName: string;
  authorPhotoUrl: string;
  createdAtMs: number;
  text: string;
  mediaUrl: string;
  audioUrl: string; // Audio support
  postType: string;
  leagueId: string;
  leagueName: string;
  // Mirrors lib/features/feed/models/public_post.dart — these three are
  // reserved for a future match-result post type (no UI creates them
  // yet, same as on Flutter) but are typed here so a doc that has them
  // doesn't get silently dropped by TS narrowing if that UI lands later.
  matchScoreHome?: number;
  matchScoreAway?: number;
  matchOpponentName?: string;
  isPromoted?: boolean;
  likeCount: number;
  commentCount: number;
  deleted: boolean;
}

// NEW: mirrors lib/features/feed/models/public_post_comment.dart.
// Firestore path: public_posts/{postId}/comments/{commentId}
export interface PublicPostComment {
  commentId: string;
  postId: string;
  authorId: string;
  authorDisplayName: string;
  authorPhotoUrl: string;
  text: string;
  createdAtMs: number;
  deleted: boolean;
}

export async function createPostWeb({
  authorId, authorDisplayName, authorPhotoUrl, text, mediaUrl = '', audioUrl = '', postType = 'text', leagueId = '', leagueName = ''
}: {
  authorId: string; authorDisplayName: string; authorPhotoUrl: string; text: string; mediaUrl?: string; audioUrl?: string; postType?: string; leagueId?: string; leagueName?: string;
}) {
  const postsRef = collection(db, 'public_posts');
  const newPostDoc = doc(postsRef);
  const now = Date.now();

  await setDoc(newPostDoc, {
    postId: newPostDoc.id,
    authorId,
    authorDisplayName,
    authorPhotoUrl,
    createdAtMs: now,
    text: text.trim().substring(0, 2000),
    mediaUrl,
    audioUrl,
    postType,
    leagueId,
    leagueName,
    matchScoreHome: 0,
    matchScoreAway: 0,
    matchOpponentName: '',
    isPromoted: false,
    likeCount: 0,
    commentCount: 0,
    deleted: false,
  });
}

export async function toggleLikeWeb(postId: string, userId: string) {
  const postRef = doc(db, 'public_posts', postId);
  const likeRef = doc(db, 'public_posts', postId, 'likes', userId);

  await runTransaction(db, async (txn) => {
    const postSnap = await txn.get(postRef);
    if (!postSnap.exists()) return;

    const currentCount = postSnap.data().likeCount || 0;
    const likeSnap = await txn.get(likeRef);

    if (likeSnap.exists()) {
      txn.delete(likeRef);
      txn.update(postRef, { likeCount: Math.max(0, currentCount - 1) });
    } else {
      txn.set(likeRef, { userId, likedAtMs: Date.now() });
      txn.update(postRef, { likeCount: currentCount + 1 });
    }
  });
}

export async function deletePostWeb(postId: string, userId: string) {
  const ref = doc(db, 'public_posts', postId);
  const snap = await getDoc(ref);
  if (!snap.exists()) return;

  if (snap.data().authorId !== userId) {
    throw new Error('You can only delete your own posts.');
  }

  await updateDoc(ref, { deleted: true });
}

// ── Comments ─────────────────────────────────────────────────────────────
//
// NEW: this repository previously had no comment support at all — Flutter's
// PublicFeedRepository (lib/features/feed/data/public_feed_repository.dart)
// has addComment/watchComments/deleteComment, and PostCard.tsx's comment
// button had no onClick handler wired to anything. A comment made on
// mobile was completely invisible on web, and web users had no way to
// comment at all. These mirror the Flutter methods exactly: a doc per
// comment in the `comments` subcollection, with `commentCount` on the
// parent post kept in sync by the same transaction that writes the
// comment — same pattern already used for `likeCount`.

export function subscribeToCommentsWeb(
  postId: string,
  callback: (comments: PublicPostComment[]) => void,
  limitCount = 200
) {
  const q = query(
    collection(db, 'public_posts', postId, 'comments'),
    orderBy('createdAtMs', 'asc'),
    limit(limitCount)
  );
  return onSnapshot(q, (snap) => {
    const comments = snap.docs
      .map(d => ({ commentId: d.id, ...d.data() } as PublicPostComment))
      .filter(c => !c.deleted);
    callback(comments);
  });
}

export async function addCommentWeb({
  postId, authorId, authorDisplayName, authorPhotoUrl, text
}: {
  postId: string; authorId: string; authorDisplayName: string; authorPhotoUrl: string; text: string;
}) {
  const trimmed = text.trim();
  if (!trimmed) throw new Error('Please write a comment first.');

  const postRef = doc(db, 'public_posts', postId);
  const commentRef = doc(collection(postRef, 'comments'));
  const now = Date.now();
  const safeText = trimmed.substring(0, 500);

  await runTransaction(db, async (txn) => {
    const postSnap = await txn.get(postRef);
    if (!postSnap.exists()) throw new Error('This post no longer exists.');
    if (postSnap.data().deleted === true) throw new Error('This post no longer exists.');

    const currentCount = postSnap.data().commentCount || 0;

    txn.set(commentRef, {
      commentId: commentRef.id,
      postId,
      authorId,
      authorDisplayName: authorDisplayName.trim(),
      authorPhotoUrl: authorPhotoUrl.trim(),
      text: safeText,
      createdAtMs: now,
      deleted: false,
    });
    txn.update(postRef, { commentCount: currentCount + 1 });
  });
}

export async function deleteCommentWeb(postId: string, commentId: string, authUid: string) {
  const ref = doc(db, 'public_posts', postId, 'comments', commentId);
  const snap = await getDoc(ref);
  if (!snap.exists()) return;
  if (snap.data().authorId !== authUid) {
    throw new Error('You can only delete your own comments.');
  }
  await updateDoc(ref, { deleted: true });
}
