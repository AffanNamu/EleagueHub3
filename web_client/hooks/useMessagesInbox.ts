'use client';

// Mirrors private_chat_list_screen.dart's PrivateChatListScreen — despite
// the "private chat" name, the Dart screen merges THREE room kinds into
// one "Messages" inbox sorted by most recent activity: private 1:1 DM
// threads, every league chatroom the user belongs to, and every organizer
// (master league) workspace chatroom the user belongs to. Web's inbox
// previously showed only private threads.

import { useEffect, useState } from 'react';
import { collection, query, orderBy, limit as fsLimit, onSnapshot } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { useLeagues } from './useLeagues';
import { useMyMasterLeagues } from './useMasterLeagues';
import { usePrivateThreads } from './usePrivateChat';
import { PrivateThread } from '@/lib/chat/privateChatRepository';

export type InboxRoomKind = 'private' | 'league' | 'organizer';

export interface InboxItem {
  kind: InboxRoomKind;
  id: string;
  title: string;
  subtitle: string;
  lastActivityMs: number;
  thread?: PrivateThread;
}

interface RoomPreview {
  preview: string;
  lastActivityMs: number;
}

function previewFromMessageDoc(data: Record<string, unknown>): RoomPreview {
  const type = typeof data.type === 'string' ? data.type.trim() : 'text';
  const text = typeof data.text === 'string' ? data.text.trim() : '';
  const senderName = typeof data.senderName === 'string' ? data.senderName.trim() : '';
  const createdAtMs = Number(data.createdAtMs) || 0;
  const deleted = data.deleted === true;

  let body: string;
  if (deleted) body = 'Message deleted';
  else if (type === 'image') body = '📷 Photo';
  else if (type === 'voice') body = '🎤 Voice message';
  else body = text || 'New message';

  return { preview: senderName ? `${senderName}: ${body}` : body, lastActivityMs: createdAtMs };
}

/** Attaches one live "latest message" listener per room id, matching
 * _RoomWatch/_attachRoomListener — added/removed as the id list changes. */
function useRoomPreviews(collectionName: 'leagues' | 'master_leagues', ids: string[]) {
  const [previews, setPreviews] = useState<Record<string, RoomPreview>>({});
  const key = ids.slice().sort().join(',');

  useEffect(() => {
    if (ids.length === 0) {
      const timer = setTimeout(() => setPreviews({}), 0);
      return () => clearTimeout(timer);
    }

    const unsubs = ids.map((id) => {
      const q = query(
        collection(db, collectionName, id, 'chatroom'),
        orderBy('createdAtMs', 'desc'),
        fsLimit(1),
      );
      return onSnapshot(
        q,
        (snap) => {
          const next = snap.empty
            ? { preview: 'No messages yet', lastActivityMs: 0 }
            : previewFromMessageDoc(snap.docs[0].data());
          setPreviews((prev) => ({ ...prev, [id]: next }));
        },
        () => {
          // A room this viewer just lost access to (left the league, etc.)
          // — leave the last-known preview in place rather than clearing it.
        },
      );
    });

    return () => unsubs.forEach((u) => u());
    // `key` is the stable dependency; `ids`/`collectionName` are covered by it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  return previews;
}

export function useMessagesInbox() {
  const [authUid, setAuthUid] = useState<string | null>(null);

  useEffect(() => {
    const unsub = auth.onAuthStateChanged((u) => setAuthUid(u?.uid ?? null));
    return () => unsub();
  }, []);

  const { threads, loading: privateLoading } = usePrivateThreads();
  const { leagues, loading: leaguesLoading } = useLeagues();
  const { created, joined, loading: mlLoading } = useMyMasterLeagues(authUid);

  const masterLeagues = [...created, ...joined];
  const leaguePreviews = useRoomPreviews('leagues', leagues.map((l) => l.id));
  const organizerPreviews = useRoomPreviews('master_leagues', masterLeagues.map((m) => m.id));

  const items: InboxItem[] = [
    ...threads.map((t) => ({
      kind: 'private' as const,
      id: t.id,
      title: '',
      subtitle: t.lastMessage || 'Say hello 👋',
      lastActivityMs: t.lastMessageAtMs,
      thread: t,
    })),
    ...leagues.map((l) => ({
      kind: 'league' as const,
      id: l.id,
      title: l.name || 'League',
      subtitle: leaguePreviews[l.id]?.preview ?? 'No messages yet',
      lastActivityMs: leaguePreviews[l.id]?.lastActivityMs ?? 0,
    })),
    ...masterLeagues.map((m) => ({
      kind: 'organizer' as const,
      id: m.id,
      title: m.name || 'Organizer',
      subtitle: organizerPreviews[m.id]?.preview ?? 'No messages yet',
      lastActivityMs: organizerPreviews[m.id]?.lastActivityMs ?? 0,
    })),
  ].sort((a, b) => b.lastActivityMs - a.lastActivityMs);

  return { items, loading: privateLoading || leaguesLoading || mlLoading, authUid };
}
