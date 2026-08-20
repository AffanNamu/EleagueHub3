// lib/services/userSearchRepository.ts
//
// Mirrors lib/features/search/data/user_search_repository.dart's
// search() method: prefix match on displayNameLower, plus an exact
// shareIdLower match (falling back to legacy case-sensitive shareId)
// so users can search by a friend's Team ID. Reads the same
// `user_search` collection the Flutter app writes to — public read
// per the Firestore rules (`allow get, list: if true`), no new
// collection or schema.

import { collection, query, orderBy, startAt, endAt, where, limit, getDocs } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface UserSearchEntry {
  userId: string;
  displayName: string;
  shareId: string;
  game: string;
  badge: string;
  avatarUrl: string;
}

function fromDoc(id: string, data: Record<string, unknown>): UserSearchEntry {
  return {
    userId: id,
    displayName: typeof data.displayName === 'string' ? data.displayName.trim() : '',
    shareId: typeof data.shareId === 'string' ? data.shareId.trim() : '',
    game: typeof data.game === 'string' ? data.game.trim() : '',
    badge: typeof data.badge === 'string' ? data.badge.trim() : '',
    avatarUrl: typeof data.avatarUrl === 'string' ? data.avatarUrl.trim() : '',
  };
}

export async function searchUsers(term: string, resultLimit = 20): Promise<UserSearchEntry[]> {
  const trimmed = term.trim();
  if (!trimmed) return [];

  const lower = trimmed.toLowerCase();
  const col = collection(db, 'user_search');
  const results = new Map<string, UserSearchEntry>();

  try {
    // 1. Prefix match on display name (case-insensitive).
    const nameSnap = await getDocs(
      query(
        col,
        orderBy('displayNameLower'),
        startAt(lower),
        endAt(`${lower}\uf8ff`),
        limit(resultLimit),
      ),
    );
    nameSnap.docs.forEach((d) => results.set(d.id, fromDoc(d.id, d.data())));

    // 2. Exact shareId match (Team ID).
    if (trimmed.length >= 3) {
      const idSnap = await getDocs(query(col, where('shareIdLower', '==', lower), limit(5)));
      idSnap.docs.forEach((d) => results.set(d.id, fromDoc(d.id, d.data())));

      // Fallback for older profiles not yet re-synced with shareIdLower.
      if (results.size === 0) {
        const idSnapExact = await getDocs(query(col, where('shareId', '==', trimmed), limit(5)));
        idSnapExact.docs.forEach((d) => results.set(d.id, fromDoc(d.id, d.data())));
      }
    }

    return Array.from(results.values());
  } catch (err) {
    console.error('[userSearchRepository] search failed:', err);
    return [];
  }
}
