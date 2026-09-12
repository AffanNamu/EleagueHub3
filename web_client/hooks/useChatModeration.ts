'use client';

// Mirrors league_chat_screen.dart's _watchModerationState(): a chat surface
// can be blocked by TWO independent moderation layers —
//   - app/chatModeration/users/{uid}  (global, allChatMuted/allChatBanned)
//   - master_leagues/{id}/memberModeration/{uid} (per-organizer-workspace,
//     chatMuted/chatBanned) — only relevant for League Chat (which belongs
//     to a master league) and Organizer Chat itself.
// Both are watched in real time so a mute/ban applied while the viewer has
// the chat open takes effect immediately, exactly like the Dart screen.

import { useEffect, useState } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

export interface ChatModerationState {
  globalMuted: boolean;
  globalBanned: boolean;
  organizerMuted: boolean;
  organizerBanned: boolean;
  resolved: boolean;
}

/** masterLeagueId is optional — pass it for League Chat (the league's own
 * masterLeagueId) or Organizer Chat (that workspace's id); omit for chats
 * with no organizer-level moderation layer (e.g. Global Chat). */
export function useChatModeration(masterLeagueId?: string | null): ChatModerationState {
  const [state, setState] = useState<ChatModerationState>({
    globalMuted: false,
    globalBanned: false,
    organizerMuted: false,
    organizerBanned: false,
    resolved: false,
  });

  useEffect(() => {
    const uid = auth.currentUser?.uid;
    if (!uid) {
      // Deferred: setting state synchronously in an effect body (rather
      // than from a subscription callback) triggers cascading renders.
      const timer = setTimeout(() => setState((s) => ({ ...s, resolved: true })), 0);
      return () => clearTimeout(timer);
    }

    const unsubs: Array<() => void> = [];

    unsubs.push(
      onSnapshot(
        doc(db, 'app', 'chatModeration', 'users', uid),
        (snap) => {
          const data = snap.data() ?? {};
          setState((s) => ({ ...s, globalMuted: data.allChatMuted === true, globalBanned: data.allChatBanned === true, resolved: true }));
        },
        () => setState((s) => ({ ...s, globalMuted: false, globalBanned: false, resolved: true })),
      ),
    );

    const mlId = (masterLeagueId || '').trim();
    if (mlId) {
      unsubs.push(
        onSnapshot(
          doc(db, 'master_leagues', mlId, 'memberModeration', uid),
          (snap) => {
            const data = snap.data() ?? {};
            setState((s) => ({ ...s, organizerMuted: data.chatMuted === true, organizerBanned: data.chatBanned === true }));
          },
          () => setState((s) => ({ ...s, organizerMuted: false, organizerBanned: false })),
        ),
      );
    }

    return () => unsubs.forEach((u) => u());
  }, [masterLeagueId]);

  return state;
}
