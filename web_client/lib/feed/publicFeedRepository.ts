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
  likeCount: number;
  commentCount: number;
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
