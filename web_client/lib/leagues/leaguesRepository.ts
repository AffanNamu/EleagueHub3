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
import { v4 as uuidv4 } from 'uuid';
import {
  LeagueData,
  Membership,
  leagueFromRemoteMap,
  membershipFromRemoteMap,
  looksLikeFirebaseUid,
} from '@/lib/models/league';
import { FootballCategory, categoryStorageValue } from '@/lib/models/footballCategory';
import { LeagueFormat, leagueFormatIndex } from '@/lib/models/leagueFormat';
import { MASTER_LEAGUE_PLANS, planFromString } from '@/types/masterLeague';
import { addCompetitionCreatedEvent } from '@/lib/masterLeagues/organizerFeedRepository';
import { fetchUserProfileByUserId } from '@/lib/services/userProfileRepository';

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

  // Capped concurrency instead of one getDoc per league fired all at once
  // — an account with many leagues could otherwise launch hundreds of
  // simultaneous reads the instant the league list loads.
  const CONCURRENCY = 8;
  const results: (Membership | null)[] = [];
  for (let i = 0; i < leagues.length; i += CONCURRENCY) {
    const batch = leagues.slice(i, i + CONCURRENCY);
    const batchResults = await Promise.all(
      batch.map(async (league) => {
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
    results.push(...batchResults);
  }

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

  // NOTE: joining a league is NOT gated by the Basic free-plan limit —
  // only creating leagues/competitions is (see leagues_list_screen.dart's
  // kIsWeb join branch and its own "Joining leagues remains available"
  // copy). A join-side limit was previously enforced here but that
  // contradicted the real Dart behavior and silently blocked Basic users
  // from joining leagues they were invited to.

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
  // Set when this league is really a competition being created inside a
  // Master League workspace. Mirrors league_create_wizard.dart's
  // widget.masterLeagueId / _inMasterLeagueMode.
  masterLeagueId?: string;
  // Only meaningful when format === 'directKnockout': the chosen bracket
  // size (4/8/16/32/64) — Direct Knockout has no fixed per-format team
  // count the way classic/uclGroup/uclSwiss do, so the caller must supply
  // it. Ignored for every other format.
  directKnockoutCapacity?: number;
}

async function writeOrganizerMembership(leagueId: string, organizerUid: string, nowMs: number): Promise<void> {
  // Non-fatal, mirroring LeaguesRepositoryFirebase._createLeagueAtExactId:
  // the league doc itself is the source of truth for who owns it: a
  // failed membership write shouldn't fail the whole creation.
  try {
    const membershipDocRef = doc(db, 'leagues', leagueId, 'memberships', organizerUid);
    await setDoc(membershipDocRef, {
      id: organizerUid,
      leagueId,
      userId: organizerUid,
      teamId: null,
      role: 0, // 0 = Organizer
      updatedAtMs: nowMs,
      version: 1,
    });
  } catch (e) {
    console.warn('[leaguesRepository] organizer membership write failed (non-fatal):', e);
  }
}

// Mirrors LeaguesRepositoryFirebase._requireMasterLeagueOwnerOrThrow: only
// the workspace owner (or a member with an 'owner'/'admin' role) may create
// competitions inside it.
async function requireMasterLeagueOwnerOrThrow(
  masterLeagueId: string,
  authUid: string,
): Promise<Record<string, unknown>> {
  const snap = await getDoc(doc(db, 'master_leagues', masterLeagueId));
  if (!snap.exists()) {
    throw new Error("We couldn't find that Master League. Please refresh and try again.");
  }

  const data = snap.data();
  const ownerId = String(data.ownerId ?? data.ownerUid ?? '').trim();
  if (ownerId && ownerId === authUid) return data;

  const roles = (data.roles && typeof data.roles === 'object') ? (data.roles as Record<string, unknown>) : {};
  const role = String(roles[authUid] ?? '').trim().toLowerCase();
  if (role === 'owner' || role === 'admin') return data;

  throw new Error('Only the Master League owner can create competitions inside it.');
}

// Mirrors LeaguesRepositoryFirebase._candidateCompetitionLeagueIdsForMasterLeague:
// Basic/Pro plans get deterministic slot ids ('mlc_{masterLeagueId}_{slot}',
// 1..plan.maxLeagues) so the competition count is enforced by which slot ids
// are already taken, rather than a separate counter doc. Elite is unlimited,
// so it just gets a random id like a standalone league.
async function candidateCompetitionLeagueIds(
  masterLeagueId: string,
  mlData: Record<string, unknown>,
): Promise<string[]> {
  const plan = planFromString(mlData.plan);
  if (plan === 'elite') {
    return [uuidv4()];
  }

  const max = MASTER_LEAGUE_PLANS[plan].maxLeagues;
  const prefix = `mlc_${masterLeagueId}_`;

  const snap = await getDocs(query(collection(db, 'leagues'), where('masterLeagueId', '==', masterLeagueId)));
  const ids = snap.docs.map((d) => d.id.trim()).filter(Boolean);

  const takenSlots = new Set<number>();
  let legacyCount = 0;
  for (const id of ids) {
    if (!id.startsWith(prefix)) {
      legacyCount += 1;
      continue;
    }
    const slot = parseInt(id.slice(prefix.length), 10);
    if (Number.isFinite(slot) && slot >= 1 && slot <= max) {
      takenSlots.add(slot);
    } else {
      legacyCount += 1;
    }
  }

  const reserved = Math.min(legacyCount, max);
  for (let i = 1; i <= reserved; i++) takenSlots.add(i);

  const limitMessage = `You have reached the limit of ${max} competitions for your ${MASTER_LEAGUE_PLANS[plan].displayName} plan.`;
  if (ids.length >= max) {
    throw new Error(limitMessage);
  }

  const candidates: string[] = [];
  for (let slot = 1; slot <= max; slot++) {
    if (!takenSlots.has(slot)) candidates.push(`${prefix}${slot}`);
  }
  if (candidates.length === 0) {
    throw new Error(limitMessage);
  }
  return candidates;
}

export async function createNewLeagueWeb(payload: CreateLeagueFormPayload): Promise<string> {
  const code = await generateUniqueJoinCode();
  const nowMs = Date.now();

  const DIRECT_KNOCKOUT_SIZES = [4, 8, 16, 32, 64];
  const maxTeams = payload.format === 'classic' ? 20
                 : payload.format === 'uclGroup' ? 32
                 : payload.format === 'uclSwiss' ? 36
                 : payload.format === 'directKnockout'
                   ? (DIRECT_KNOCKOUT_SIZES.includes(payload.directKnockoutCapacity ?? -1)
                       ? (payload.directKnockoutCapacity as number)
                       : 16)
                 : payload.worldCupFormat === 'fifa2022' ? 32 : 48;

  const derivedOrganizerUserId = deriveShareIdFromUid(payload.organizerUid) || payload.organizerUid;
  const masterLeagueId = (payload.masterLeagueId || '').trim();

  // STRICT PARITY: Fully matching the Flutter Model and Firestore Rules constraints
  const buildDocumentPayload = (id: string) => ({
    id,
    name: payload.name.trim(),
    masterLeagueId,
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
      // Matches LeagueSettings.defaultsFor(): every format gets groupSize:4
      // and swissRounds:8 written unconditionally, not just the formats
      // that use them — leaving these out (as this used to) makes them
      // default to the wrong value on read (swissRounds: 0) and breaks
      // Swiss-format knockout generation's "finish all N rounds" check.
      doubleRoundRobin: payload.homeAway,
      groupSize: 4,
      swissRounds: 8,
      lastPulledAtMs: 0,
      worldCupFormat: payload.format === 'worldCup' ? payload.worldCupFormat : 'fifa2022',
    },
  });

  if (!masterLeagueId) {
    const newLeagueDoc = doc(collection(db, 'leagues'));
    await setDoc(newLeagueDoc, buildDocumentPayload(newLeagueDoc.id));
    await writeOrganizerMembership(newLeagueDoc.id, payload.organizerUid, nowMs);
    return newLeagueDoc.id;
  }

  // ── Master League competition path ──────────────────────────────────────
  const mlData = await requireMasterLeagueOwnerOrThrow(masterLeagueId, payload.organizerUid);
  const candidates = await candidateCompetitionLeagueIds(masterLeagueId, mlData);

  let lastError: unknown = null;
  for (const candidateId of candidates) {
    try {
      const leagueRef = doc(db, 'leagues', candidateId);
      await setDoc(leagueRef, buildDocumentPayload(candidateId));
      await writeOrganizerMembership(candidateId, payload.organizerUid, nowMs);

      // Non-fatal: lets followers of this workspace see the new
      // competition in their Followed Organizer Feed.
      try {
        const ownerProfile = await fetchUserProfileByUserId(payload.organizerUid);
        const actorName = ownerProfile?.teamName.trim() || 'Organizer';
        await addCompetitionCreatedEvent({
          masterLeagueId,
          leagueId: candidateId,
          actorId: payload.organizerUid,
          actorName,
          competitionName: payload.name.trim(),
        });
      } catch (e) {
        console.warn('[leaguesRepository] addCompetitionCreatedEvent failed (non-fatal):', e);
      }

      return candidateId;
    } catch (e) {
      lastError = e;
      // Someone else claimed this slot between our read and our write —
      // Firestore evaluates the write as an "update" against their doc,
      // which the security rules reject. Try the next candidate slot.
      if (e instanceof Error && 'code' in e && (e as { code?: string }).code === 'permission-denied') continue;
      throw e;
    }
  }

  throw lastError instanceof Error ? lastError : new Error('Failed to create the competition. Please try again.');
}
