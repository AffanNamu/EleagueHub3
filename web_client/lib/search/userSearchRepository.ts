import { collection, getDocs, query, where, orderBy, limit, startAt, endAt, doc, setDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';

export interface UserSearchEntry {
  userId: string;
  displayName: string;
  shareId: string;
  game: string;
  badge: string;
  avatarUrl: string;
  country: string;
  usernameLower: string;
}

export async function fetchNearbyTeamsWeb(countryCode: string, selfUid: string, limitCount = 20): Promise<UserSearchEntry[]> {
  const cc = countryCode.trim().toUpperCase();
  if (!cc) return [];

  try {
    const q = query(
      collection(db, 'user_search'),
      where('country', '==', cc),
      orderBy('updatedAtMs', 'desc'),
      limit(limitCount + 1)
    );
    
    const snap = await getDocs(q);
    const results: UserSearchEntry[] = [];
    
    snap.forEach(d => {
      if (d.id !== selfUid) {
        results.push({ userId: d.id, ...d.data() } as UserSearchEntry);
      }
    });

    return results.slice(0, limitCount);
  } catch (err) {
    console.error('[UserSearchRepository] fetchNearbyTeamsWeb failed:', err);
    return [];
  }
}

export async function searchUsersWeb(searchQuery: string, selfUid: string, limitCount = 20): Promise<UserSearchEntry[]> {
  const trimmed = searchQuery.trim();
  let lower = trimmed.toLowerCase();
  if (lower.startsWith('@')) lower = lower.substring(1);
  
  if (!lower) return [];

  try {
    const resultsMap = new Map<string, UserSearchEntry>();

    // 1. Prefix match on Display Name
    const nameQ = query(
      collection(db, 'user_search'),
      orderBy('displayNameLower'),
      startAt(lower),
      endAt(lower + '\uf8ff'),
      limit(limitCount)
    );
    const nameSnap = await getDocs(nameQ);
    nameSnap.forEach(d => resultsMap.set(d.id, { userId: d.id, ...d.data() } as UserSearchEntry));

    // 2. Exact match on Username (triggers for @ prefix or >= 3 chars)
    if (trimmed.startsWith('@') || lower.length >= 3) {
      const usernameQ = query(
        collection(db, 'user_search'),
        where('usernameLower', '==', lower),
        limit(5)
      );
      const usernameSnap = await getDocs(usernameQ);
      usernameSnap.forEach(d => resultsMap.set(d.id, { userId: d.id, ...d.data() } as UserSearchEntry));
    }

    // 3. Exact match on Share ID
    if (trimmed.length >= 3) {
      const idQ = query(
        collection(db, 'user_search'),
        where('shareIdLower', '==', lower),
        limit(5)
      );
      const idSnap = await getDocs(idQ);
      idSnap.forEach(d => resultsMap.set(d.id, { userId: d.id, ...d.data() } as UserSearchEntry));
      
      // Fallback exact match on raw shareId if needed
      if (resultsMap.size === 0) {
        const idExactQ = query(
          collection(db, 'user_search'),
          where('shareId', '==', trimmed),
          limit(5)
        );
        const idExactSnap = await getDocs(idExactQ);
        idExactSnap.forEach(d => resultsMap.set(d.id, { userId: d.id, ...d.data() } as UserSearchEntry));
      }
    }

    // Filter out self and convert to array
    const finalResults = Array.from(resultsMap.values()).filter(u => u.userId !== selfUid);
    return finalResults.slice(0, limitCount);
  } catch (err) {
    console.error('[UserSearchRepository] searchUsersWeb failed:', err);
    return [];
  }
}
