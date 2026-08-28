/*lib/leagues/leaguesRepository.ts*/

import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  where,
  orderBy,
  limit,
  updateDoc,
  setDoc,
  deleteDoc,
  arrayRemove,
  arrayUnion,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';
import {
  LeagueData,
  Membership,
  leagueFromRemoteMap,
  membershipFromRemoteMap,
  looksLikeFirebaseUid,
} from '@/lib/models/league';
import { FootballCategory, categoryStorageValue } from '@/lib/models/footballCategory';
import { LeagueFormat, leagueFormatIndex } from '@/lib/models/leagueFormat';

export async function fetchLeaguesForUser(uid: string): Promise<LeagueData[]> {
  const trimmed = uid.trim();
  if (!trimmed) return [];

  const docsById = new Map<string, Record<string, unknown>>();
  const leaguesCol = collection(db, 'leagues');

  const queries = [
    query(leaguesCol, where('memberIds', 'array-contains', trimmed)),
    query(leaguesCol, where('organizerUid', '==', trimmed)),
    query(leaguesCol, where('ownerUid', '==', trimmed)),
  ];

  if (looksLikeFirebaseUid(trimmed)) {
    queries.push(query(leaguesCol, where('ownerId', '==', trimmed)));
    queries.push(query(leaguesCol, where('organizerUserId', '==', trimmed)));
  }

  await Promise.all(
    queries.map(async (q) => {
      try {
        const snap = await getDocs(q);
        snap.forEach((d) => {
          if (!docsById.has(d.id)) docsById.set(d.id, d.data());
        });
      } catch (e) {
        console.warn('[leaguesRepository] a leagues query failed:', e);
      }
    }),
  );

  const leagues: LeagueData[] = [];
  for (const [id, data] of docsById.entries()) {
    try {
      leagues.push(leagueFromRemoteMap({ ...data, id: (data.id as string) || id }));
    } catch (e) {
      console.warn(`[leaguesRepository] failed to parse league ${id}:`, e);
    }
  }
  return leagues;
}

export async function fetchMembershipsForUser(uid: string, leagues: LeagueData[]): Promise<Membership[]> {
  const trimmed = uid.trim();
  if (!trimmed || leagues.length === 0) return [];

  const results = await Promise.all(
    leagues.map(async (league) => {
      try {
        const snap = await getDoc(doc(db, 'leagues', league.id, 'memberships', trimmed));
        if (snap.exists()) {
          return membershipFromRemoteMap({ ...snap.data(), id: snap.id });
        }
      } catch (e) {
        console.warn(`[leaguesRepository] membership read failed for ${league.id}:`, e);
      }
      return null;
    }),
  );

  return results.filter((m): m is Membership => m !== null);
}

export async function countParticipants(leagueId: string): Promise<number> {
  const snap = await getDocs(collection(db, 'leagues', leagueId, 'memberships'));
  let count = 0;
  snap.forEach((d) => {
    const data = d.data();
    const uid = typeof data.userId === 'string' ? data.userId.trim() : '';
    const roleIdx = Number(data.role);
    if (uid && (roleIdx === 0 || roleIdx === 1)) count++;
  });
  return count;
}

export interface LatestAnnouncement {
  title: string;
  message: string;
}

export async function fetchLatestAnnouncement(leagueId: string): Promise<LatestAnnouncement | null> {
  try {
    const q = query(
      collection(db, 'leagues', leagueId, 'announcements'),
      orderBy('createdAtMs', 'desc'),
      limit(1),
    );
    const snap = await getDocs(q);
    if (snap.empty) return null;
    const data = snap.docs[0].data();
    return {
      title: typeof data.title === 'string' ? data.title : '',
      message: typeof data.message === 'string' ? data.message : '',
    };
  } catch (e) {
    console.warn(`[leaguesRepository] announcement fetch failed for ${leagueId}:`, e);
    return null;
  }
}

export async function detectPremiumUser(uid: string): Promise<boolean> {
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    const data = snap.data() ?? {};
    if (data.isPremium === true) return true;

    const premiumExpiresAtMs = Number(data.premiumExpiresAtMs) || 0;
    if (premiumExpiresAtMs > Date.now()) return true;

    const activePlanId = typeof data.activePlanId === 'string' ? data.activePlanId.trim() : '';
    if (activePlanId === 'pro' || activePlanId === 'elite') {
      const planExpiresAtMs = Number(data.planExpiresAtMs) || 0;
      if (planExpiresAtMs > Date.now()) return true;
    }
  } catch (e) {
    console.warn('[leaguesRepository] detectPremiumUser failed:', e);
  }
  return false;
}

export async function countCreatedLeagues(uid: string): Promise<number> {
  const trimmed = uid.trim();
  if (!trimmed) return 0;

  const ids = new Set<string>();
  const leaguesCol = collection(db, 'leagues');

  try {
    const snap = await getDocs(query(leaguesCol, where('organizerUid', '==', trimmed)));
    snap.forEach((d) => ids.add(d.id));
  } catch (e) {
    console.warn('[leaguesRepository] countCreatedLeagues organizerUid query failed:', e);
  }

  if (looksLikeFirebaseUid(trimmed)) {
    try {
      const snap = await getDocs(query(leaguesCol, where('organizerUserId', '==', trimmed)));
      snap.forEach((d) => ids.add(d.id));
    } catch (e) {
      console.warn('[leaguesRepository] countCreatedLeagues organizerUserId query failed:', e);
    }
  }

  return ids.size;
}

export async function leaveLeagueWeb(leagueId: string, uid: string): Promise<void> {
  // STRICT PARITY: Prevent Owners from leaving their own league from the list view
  const leagueRef = doc(db, 'leagues', leagueId);
  const snap = await getDoc(leagueRef);
  
  if (!snap.exists()) {
    throw new Error("We couldn't find this league. Please refresh and try again.");
  }

  const data = snap.data();
  if (
    data.organizerUid === uid ||
    data.ownerUid === uid ||
    data.ownerId === uid ||
    data.organizerUserId === uid
  ) {
    throw new Error("League owners cannot remove their own league from the list here. Please use the owner/admin area.");
  }

  // Remove memberId array entry
  await updateDoc(leagueRef, {
    memberIds: arrayRemove(uid),
    updatedAtMs: Date.now(),
  });

  // STRICT PARITY: Delete membership sub-document
  try {
    await deleteDoc(doc(db, 'leagues', leagueId, 'memberships', uid));
  } catch (e) {
    console.warn('Membership delete failed (non-fatal)', e);
  }
}

export async function joinLeagueByCode(
  code: string,
  uid: string,
  mode: 'participant' | 'viewer',
): Promise<string> {
  const normalized = code.trim().toUpperCase();
  if (!normalized) {
    throw new Error('Please enter a valid league code.');
  }

  let snap;
  try {
    snap = await getDocs(query(collection(db, 'leagues'), where('code', '==', normalized), limit(1)));
  } catch (e: any) {
    // STRICT PARITY: Handle Firestore Rules throwing permission-denied on a code query
    if (e.code === 'permission-denied') {
      throw new Error("We couldn't find a league with that code. Please check the code and try again.");
    }
    throw e;
  }

  if (snap.empty) {
    throw new Error("We couldn't find a league with that code.");
  }

  const leagueDoc = snap.docs[0];
  const leagueId = leagueDoc.id;
  const leagueData = leagueDoc.data();

  // STRICT PARITY: Enforce the 3-League Free Limit for Joining
  const memberIds = leagueData.memberIds || [];
  if (!memberIds.includes(uid)) {
    const isPremium = await detectPremiumUser(uid);
    if (!isPremium) {
      const userLeaguesSnap = await getDocs(query(collection(db, 'leagues'), where('memberIds', 'array-contains', uid)));
      if (userLeaguesSnap.size >= 3) {
        throw new Error('Free users can only have 3 leagues total on the leagues screen. Upgrade to Premium to join more leagues.');
      }
    }
  }

  // First write memberIds to satisfy Firestore Rules for membership subcollection write
  await updateDoc(doc(db, 'leagues', leagueId), {
    memberIds: arrayUnion(uid),
    updatedAtMs: Date.now(),
  });

  if (mode === 'participant') {
    try {
      const membershipRef = doc(db, 'leagues', leagueId, 'memberships', uid);
      const existing = await getDoc(membershipRef);
      if (!existing.exists()) {
        await setDoc(membershipRef, {
          id: uid,
          leagueId,
          userId: uid,
          teamId: null,
          role: 1, // LeagueRole.member
          updatedAtMs: Date.now(),
          version: 1,
        }, { merge: true });
      }
    } catch (e) {
      console.warn('Membership write failed after memberIds update (non-fatal)', e);
    }
  }

  return leagueId;
}

function generateJoinCodeRaw(length = 6): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

async function generateUniqueJoinCode(): Promise<string> {
  for (let i = 0; i < 6; i++) {
    const code = generateJoinCodeRaw();
    const snap = await getDocs(query(collection(db, 'leagues'), where('code', '==', code), limit(1)));
    if (snap.empty) return code;
  }
  return generateJoinCodeRaw(8);
}

function deriveShareIdFromUid(uid: string): string {
  const clean = uid.replace(/[^A-Za-z0-9]/g, '').trim();
  if (!clean) return '';
  const base = clean.length >= 8 ? clean.substring(0, 8) : clean.padEnd(8, 'X');
  return `eS${base}`;
}

export interface CreateLeagueFormPayload {
  name: string;
  description: string;
  leagueImageUrl: string;
  sponsorImageUrl: string;
  format: LeagueFormat;
  worldCupFormat: number | string; // Handled dynamically 
  category: FootballCategory;
  isPrivate: boolean;
  homeAway: boolean;
  organizerUid: string;
}

export async function createNewLeagueWeb(payload: CreateLeagueFormPayload): Promise<string> {
  const code = await generateUniqueJoinCode();
  const leaguesRef = collection(db, 'leagues');
  const newLeagueDoc = doc(leaguesRef);
  const nowMs = Date.now();

  const maxTeams = payload.format === 'classic' ? 20 
                 : payload.format === 'uclGroup' ? 32 
                 : payload.format === 'uclSwiss' ? 36 
                 : payload.worldCupFormat === 'fifa2022' ? 32 : 48;

  const derivedOrganizerUserId = deriveShareIdFromUid(payload.organizerUid) || payload.organizerUid;

  // STRICT PARITY: Fully matching the Flutter Model and Firestore Rules constraints
  const documentPayload = {
    id: newLeagueDoc.id,
    name: payload.name.trim(),
    masterLeagueId: '',
    description: payload.description.trim(),
    leagueImageUrl: payload.leagueImageUrl.trim(),
    sponsorImageUrl: payload.sponsorImageUrl.trim(),
    viewerCapacity: 0,
    couponsEnabled: false,
    couponDiscountPercent: 0,
    couponCount: 0,
    homeAwayEnabled: payload.homeAway,
    footballCategory: categoryStorageValue(payload.category),
    format: leagueFormatIndex(payload.format), 
    isPrivate: payload.isPrivate,
    region: 'Global',
    maxTeams: maxTeams,
    season: '2026',
    
    // Crucial for Firebase Rules evaluation:
    organizerUid: payload.organizerUid,
    ownerUid: payload.organizerUid,
    ownerId: payload.organizerUid,
    organizerUserId: derivedOrganizerUserId,
    
    code: code,
    qrPayloadOverride: '',
    updatedAtMs: nowMs,
    createdAtMs: nowMs,
    version: 1,
    memberIds: [payload.organizerUid],
    settings: {
      doubleRoundRobin: payload.homeAway,
      lastPulledAtMs: 0,
      worldCupFormat: payload.format === 'worldCup' ? payload.worldCupFormat : 'fifa2022'
    }
  };

  await setDoc(newLeagueDoc, documentPayload);

  // Add the creator's membership immediately
  const membershipDocRef = doc(db, 'leagues', newLeagueDoc.id, 'memberships', payload.organizerUid);
  await setDoc(membershipDocRef, {
    id: payload.organizerUid,
    leagueId: newLeagueDoc.id,
    userId: payload.organizerUid,
    teamId: null,
    role: 0, // 0 = Organizer
    updatedAtMs: nowMs,
    version: 1,
  });

  return newLeagueDoc.id;
}
