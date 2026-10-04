// web_client/lib/reactions/reactionsRepository.ts
//
// Generic emoji-reaction repository usable against ANY message/post doc
// across the app's reaction surfaces (global/league/organizer chat,
// private DM messages, feed posts) -- all five share the identical
// `<parent>/reactions/{uid}` subcollection shape validated by
// firestore.rules' validReactionCreate(). Mirrors
// lib/core/reactions/reactions_repository.dart.

import { collection, doc, onSnapshot, getDoc, setDoc, deleteDoc, DocumentReference } from 'firebase/firestore';
import { auth } from '@/lib/firebase';
import { MessageReaction, ReactionSummary, summarizeReactions } from '@/types/reactions';

function reactionsCol(parentRef: DocumentReference) {
  return collection(parentRef, 'reactions');
}

/** Live reaction summary for a message/post. Returns an unsubscribe fn. */
export function watchReactions(
  parentRef: DocumentReference,
  onChange: (summary: ReactionSummary) => void
): () => void {
  return onSnapshot(reactionsCol(parentRef), (snap) => {
    const myUid = auth.currentUser?.uid || null;
    const reactions: MessageReaction[] = snap.docs.map((d) => {
      const data = d.data() as Partial<MessageReaction>;
      return {
        uid: (data.uid as string) || d.id,
        emoji: (data.emoji as string) || '',
        reactedAtMs: (data.reactedAtMs as number) || 0,
      };
    });
    onChange(summarizeReactions(reactions, myUid));
  });
}

/**
 * Sets the caller's reaction to `emoji`. Picking the same emoji again
 * removes it (toggle-off); picking a different one replaces it -- one
 * reaction per user per message, like Messenger/Discord rather than
 * Slack's multi-reaction-per-user model.
 */
export async function toggleReaction(parentRef: DocumentReference, emoji: string): Promise<void> {
  const uid = auth.currentUser?.uid;
  if (!uid) return;
  const ref = doc(reactionsCol(parentRef), uid);
  const existing = await getDoc(ref);
  if (existing.exists() && existing.data()?.emoji === emoji) {
    await deleteDoc(ref);
  } else {
    await setDoc(ref, { uid, emoji, reactedAtMs: Date.now() });
  }
}
