import { collection, getDocs, getDoc, query, where, orderBy, limit, startAt, endAt, doc, setDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { resolveCountryCodeWeb } from '@/lib/countryResolver';

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

/**
 * Mirrors UserSearchRepository.syncSelfIndex() — keeps this user's
 * `user_search/{uid}` doc (the index every search/nearby query above
 * reads) up to date. Called whenever the fields it covers change:
 * display name, avatar, or (indirectly, via the profile save flow on
 * mobile) game. Best-effort — never throws, matching the Dart repo's
 * "non-fatal" background-sync behavior.
 */
export async function syncSelfIndexWeb(params: {
  displayName: string;
  shareId: string;
  game?: string;
  badge?: string;
  avatarUrl: string;
  country?: string;
  usernameLower?: string;
}) {
  const uid = auth.currentUser?.uid.trim();
  if (!uid) return;

  try {
    const displayName = params.displayName.trim() || (auth.currentUser?.displayName ?? '').trim();
    const shareId = params.shareId.trim();

    const payload: Record<string, unknown> = {
      userId: uid,
      displayName,
      displayNameLower: displayName.toLowerCase(),
      shareId,
      shareIdLower: shareId.toLowerCase(),
      game: (params.game ?? '').trim(),
      badge: (params.badge ?? '').trim(),
      avatarUrl: params.avatarUrl.trim(),
      updatedAtMs: Date.now(),
    };

    const country = (params.country ?? '').trim().toUpperCase();
    if (country) payload.country = country;

    const usernameLower = (params.usernameLower ?? '').trim().toLowerCase();
    if (usernameLower) payload.usernameLower = usernameLower;

    await setDoc(doc(db, 'user_search', uid), payload, { merge: true });
  } catch (err) {
    console.warn('[userSearchRepository] syncSelfIndexWeb failed (non-fatal):', err);
  }
}

/**
 * Mirrors UserSearchRepository.syncUsername() — writes ONLY
 * userId/usernameLower/updatedAtMs, called right after a username
 * reservation commits (both an explicit edit and lazy auto-assignment)
 * so the search index never drifts from the authoritative username doc.
 */
export async function syncUsernameWeb(usernameLower: string) {
  const uid = auth.currentUser?.uid.trim();
  const lower = usernameLower.trim().toLowerCase();
  if (!uid || !lower) return;

  try {
    await setDoc(
      doc(db, 'user_search', uid),
      { userId: uid, usernameLower: lower, updatedAtMs: Date.now() },
      { merge: true },
    );
  } catch (err) {
    console.warn('[userSearchRepository] syncUsernameWeb failed (non-fatal):', err);
  }
}

/**
 * Mirrors UserSearchRepository.backfillDisplayNameIfMissing() — a
 * self-heal for accounts whose user_search doc still has a blank name
 * (e.g. it was never synced before this fix existed). Only ever touches
 * displayName/displayNameLower, so it can never clobber other fields.
 */
export async function backfillDisplayNameIfMissingWeb(fallbackDisplayName: string) {
  const uid = auth.currentUser?.uid.trim();
  const name = fallbackDisplayName.trim();
  if (!uid || !name) return;

  try {
    const snap = await getDoc(doc(db, 'user_search', uid));
    const existing = typeof snap.data()?.displayName === 'string' ? snap.data()!.displayName.trim() : '';
    if (existing) return;

    await setDoc(
      doc(db, 'user_search', uid),
      { userId: uid, displayName: name, displayNameLower: name.toLowerCase(), updatedAtMs: Date.now() },
      { merge: true },
    );
  } catch (err) {
    console.warn('[userSearchRepository] backfillDisplayNameIfMissingWeb failed (non-fatal):', err);
  }
}

/**
 * Mirrors UserSearchRepository.backfillCountryIfMissing() — self-heals
 * "Teams Near You" eligibility for accounts that predate the country
 * field, or never triggered syncSelfIndexWeb.
 */
export async function backfillCountryIfMissingWeb() {
  const uid = auth.currentUser?.uid.trim();
  if (!uid) return;

  try {
    const snap = await getDoc(doc(db, 'user_search', uid));
    const existing = typeof snap.data()?.country === 'string' ? snap.data()!.country.trim() : '';
    if (existing) return;

    const resolved = (await resolveCountryCodeWeb()).trim().toUpperCase();
    if (!resolved) return;

    await setDoc(
      doc(db, 'user_search', uid),
      { userId: uid, country: resolved, updatedAtMs: Date.now() },
      { merge: true },
    );
  } catch (err) {
    console.warn('[userSearchRepository] backfillCountryIfMissingWeb failed (non-fatal):', err);
  }
}
