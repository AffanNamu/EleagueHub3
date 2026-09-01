import { useState, useEffect } from 'react';
// FIXED: `doc` was used below (doc(db, 'discussion_threads', threadId))
// but never imported — this threw a ReferenceError the moment anyone
// opened a discussion thread on web (useDiscussionDetail runs on mount).
import { collection, doc, query, where, orderBy, limit, onSnapshot } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { DiscussionThread, DiscussionReply } from '@/lib/discovery/discoveryRepository';
import { LeagueData, leagueFromRemoteMap } from '@/lib/models/league';

export function usePublicCompetitions() {
  const [leagues, setLeagues] = useState<LeagueData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(
      collection(db, 'leagues'),
      where('isPrivate', '==', false),
      orderBy('updatedAtMs', 'desc'),
      limit(30)
    );
    const unsub = onSnapshot(q, (snap) => {
      setLeagues(snap.docs.map(d => leagueFromRemoteMap({ id: d.id, ...d.data() })));
      setLoading(false);
    });
    return () => unsub();
  }, []);

  return { leagues, loading };
}

export function useDiscussionThreads() {
  const [threads, setThreads] = useState<DiscussionThread[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const q = query(
      collection(db, 'discussion_threads'),
      where('deleted', '==', false),
      orderBy('lastReplyAtMs', 'desc'),
      limit(40)
    );
    const unsub = onSnapshot(q, (snap) => {
      setThreads(snap.docs.map(d => ({ ...d.data(), threadId: d.id } as DiscussionThread)));
      setLoading(false);
    });
    return () => unsub();
  }, []);

  return { threads, loading };
}

export function useDiscussionDetail(threadId: string) {
  const [thread, setThread] = useState<DiscussionThread | null>(null);
  const [replies, setReplies] = useState<DiscussionReply[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!threadId) return;
    const unsubThread = onSnapshot(doc(db, 'discussion_threads', threadId), (d) => {
      if (d.exists() && !d.data().deleted) setThread({ ...d.data(), threadId: d.id } as DiscussionThread);
      else setThread(null);
    });

    const q = query(
      collection(db, 'discussion_threads', threadId, 'replies'),
      where('deleted', '==', false),
      orderBy('createdAtMs', 'asc'),
      limit(200)
    );
    const unsubReplies = onSnapshot(q, (snap) => {
      setReplies(snap.docs.map(d => ({ ...d.data(), replyId: d.id } as DiscussionReply)));
      setLoading(false);
    });

    return () => { unsubThread(); unsubReplies(); };
  }, [threadId]);

  return { thread, replies, loading };
}
