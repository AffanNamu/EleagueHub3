// web_client/types/reactions.ts
//
// Mirrors lib/core/reactions/message_reaction.dart -- same fixed emoji
// palette, same per-user doc shape, kept in STRICT PARITY with
// firestore.rules' validReactionEmoji()/validReactionCreate().

export const REACTION_EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '👏'] as const;
export type ReactionEmoji = (typeof REACTION_EMOJIS)[number];

export interface MessageReaction {
  uid: string;
  emoji: string;
  reactedAtMs: number;
}

export interface ReactionSummary {
  /** emoji -> how many users picked it. */
  counts: Record<string, number>;
  /** The signed-in user's own reaction, if any. */
  myEmoji: string | null;
}

export const EMPTY_REACTION_SUMMARY: ReactionSummary = { counts: {}, myEmoji: null };

export function summarizeReactions(reactions: MessageReaction[], myUid: string | null): ReactionSummary {
  const counts: Record<string, number> = {};
  let myEmoji: string | null = null;
  for (const r of reactions) {
    if (!r.emoji) continue;
    counts[r.emoji] = (counts[r.emoji] || 0) + 1;
    if (myUid && r.uid === myUid) myEmoji = r.emoji;
  }
  return { counts, myEmoji };
}

/** Emojis in REACTION_EMOJIS order (stable pill row), only ones with >=1 reaction. */
export function orderedReactionEntries(summary: ReactionSummary): Array<[string, number]> {
  return REACTION_EMOJIS.filter((e) => summary.counts[e] > 0).map((e) => [e, summary.counts[e]]);
}
