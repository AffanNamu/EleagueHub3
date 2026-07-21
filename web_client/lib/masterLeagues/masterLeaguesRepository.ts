import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  where,
  orderBy,
  limit as fsLimit,
  setDoc,
  updateDoc,
  deleteDoc,
  runTransaction,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import {
  MasterLeague,
  MasterLeaguePlanId,
  MASTER_LEAGUE_PLANS,
  masterLeagueFromDoc,
} from '@/types/masterLeague';

// Mirrors master_leagues_repository_firebase.dart, trimmed to what the
// web screens need. The slot-allocation fix (direct doc.get() per
// candidate id, never a where() query) is carried over verbatim —
// see the long comment in the Dart file for why that matters.

function requireUid(): string {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid) throw new Error('Please sign in and try again.');
  return uid;
}

function col() {
  return collection(db, 'master_leagues');
}

export async function getById(id: string): Promise<MasterLeague | null> {
  const snap = await getDoc(doc(db, 'master_leagues', id.trim()));
  if (!snap.exists()) return null;
  return masterLeagueFromDoc(snap.id, snap.data());
}

export async function fetchCreated(uid: string): Promise<MasterLeague[]> {
  const q = query(col(), where('ownerId', '==', uid));
  const snap = await getDocs(q);
  const list = snap.docs.map((d) => masterLeagueFromDoc(d.id, d.data()));
  list.sort((a, b) => b.updatedAtMs - a.updatedAtMs);
  return list;
}

export async function fetchJoined(uid: string): Promise<MasterLeague[]> {
  const q = query(col(), where('memberIds', 'array-contains', uid));
  const snap = await getDocs(q);
  const list = snap.docs
    .map((d) => masterLeagueFromDoc(d.id, d.data()))
    .filter((ml) => ml.ownerId !== uid);
  list.sort((a, b) => b.updatedAtMs - a.updatedAtMs);
  return list;
}

export async function countOwnedWorkspaces(uid: string): Promise<number> {
  const q = query(col(), where('ownerId', '==', uid));
  const snap = await getDocs(q);
  return snap.size;
}

export async function discoverAll(limitCount = 20): Promise<MasterLeague[]> {
  const q = query(col(), orderBy('updatedAtMs', 'desc'), fsLimit(limitCount));
  const snap = await getDocs(q);
  return snap.docs
    .map((d) => masterLeagueFromDoc(d.id, d.data()))
    .filter((ml) => ml.name.trim().length > 0 && (ml.purchaseStatus === '' || ml.purchaseStatus === 'active'));
}

export async function discoverVerified(limitCount = 12): Promise<MasterLeague[]> {
  const q = query(col(), where('verifiedBadge', '==', true));
  const snap = await getDocs(q);
  const list = snap.docs.map((d) => masterLeagueFromDoc(d.id, d.data()));
  list.sort((a, b) => b.followersCount - a.followersCount || b.updatedAtMs - a.updatedAtMs);
  return list.slice(0, limitCount);
}

function slotIdFor(uid: string, slot: number): string {
  return `ml_${uid}_${slot}`;
}

/**
 * Finds a free slot id for the given plan by checking each candidate
 * document DIRECTLY (get by id) — never inferring "free" from a query,
 * since a stale/unindexed doc at that id would silently turn the
 * intended `create` into a rule-checked `update` and fail.
 */
export async function allocateSlotId(uid: string, plan: MasterLeaguePlanId): Promise<string> {
  if (plan === 'elite') {
    // Elite ids are randomly generated — collisions are practically impossible.
    return doc(col()).id;
  }

  const maxSlots = MASTER_LEAGUE_PLANS[plan].maxMasterLeagues;
  for (let slot = 1; slot <= maxSlots; slot++) {
    const candidate = slotIdFor(uid, slot);
    const snap = await getDoc(doc(db, 'master_leagues', candidate));
    if (!snap.exists()) return candidate;
  }

  throw new Error(
    `You have reached the limit of ${maxSlots} master league${maxSlots === 1 ? '' : 's'} for the ${MASTER_LEAGUE_PLANS[plan].displayName} plan.`,
  );
}

export interface CreateWorkspaceInput {
  name: string;
  plan: MasterLeaguePlanId;
}

/** Writes the master_leagues doc directly — used for Basic (free) and
 * for Pro/Elite once the ID token already carries the matching claims
 * (see lib/masterLeagues/entitlements.ts). */
export async function create(input: CreateWorkspaceInput): Promise<MasterLeague> {
  const uid = requireUid();
  const name = input.name.trim();
  if (!name) throw new Error('Please enter a name for your Master League.');
  if (name.length > 60) throw new Error('Master League name is too long.');

  const id = await allocateSlotId(uid, input.plan);
  const ref = doc(db, 'master_leagues', id);

  await setDoc(ref, {
    name,
    ownerId: uid,
    ownerUid: uid,
    createdAt: serverTimestamp(),
    purchaseStatus: 'active',
    memberIds: [uid],
    roles: { [uid]: 'owner' },
    staffShareIds: {},
    updatedAtMs: Date.now(),
    plan: input.plan,
    bannerUrl: '',
    logoUrl: '',
    bio: '',
    badge: '',
    socialLinks: {},
    totalTournamentsCreated: 0,
    totalParticipantsTeams: 0,
    totalMatches: 0,
    followersCount: 0,
    createdViaAttemptId: '',
    sourcePaymentId: '',
    sourceReceiptId: '',
    verificationStatus: 'none',
    verifiedBadge: false,
    verificationRequestId: '',
    verificationReceiptId: '',
    verificationPaymentId: '',
    verificationProvider: '',
    verificationRequestedAtMs: 0,
    verificationApprovedAtMs: 0,
    verificationExpiresAtMs: 0,
    verificationReviewedBy: '',
    verificationNote: '',
    verificationRequestType: 'initial',
  });

  const fresh = await getDoc(ref);
  return masterLeagueFromDoc(fresh.id, fresh.data() ?? {});
}

export async function rename(masterLeagueId: string, newName: string): Promise<void> {
  const uid = requireUid();
  const name = newName.trim().slice(0, 60);
  if (!name) throw new Error('Please enter a valid Master League name.');

  const ref = doc(db, 'master_leagues', masterLeagueId.trim());
  const snap = await getDoc(ref);
  if (!snap.exists()) throw new Error("We couldn't find that Master League.");
  if ((snap.data().ownerId ?? snap.data().ownerUid) !== uid) {
    throw new Error('Only the Master League owner can rename it.');
  }

  await updateDoc(ref, { name, updatedAtMs: Date.now() });
}

export async function deleteWorkspace(masterLeagueId: string): Promise<void> {
  const uid = requireUid();
  const ref = doc(db, 'master_leagues', masterLeagueId.trim());
  const snap = await getDoc(ref);
  if (!snap.exists()) return;
  if ((snap.data().ownerId ?? snap.data().ownerUid) !== uid) {
    throw new Error('Only the Master League owner can perform this action.');
  }
  await deleteDoc(ref);
}

export async function isFollowing(masterLeagueId: string, uid: string): Promise<boolean> {
  if (!uid) return false;
  const snap = await getDoc(doc(db, 'master_leagues', masterLeagueId, 'followers', uid));
  return snap.exists();
}

export async function followWorkspace(masterLeagueId: string): Promise<void> {
  const uid = requireUid();
  const mlRef = doc(db, 'master_leagues', masterLeagueId);
  const followerRef = doc(db, 'master_leagues', masterLeagueId, 'followers', uid);

  await runTransaction(db, async (txn) => {
    const followerSnap = await txn.get(followerRef);
    if (followerSnap.exists()) return;

    const mlSnap = await txn.get(mlRef);
    if (!mlSnap.exists()) throw new Error("We couldn't find that Master League.");
    if ((mlSnap.data().ownerId ?? mlSnap.data().ownerUid) === uid) {
      throw new Error('You cannot follow your own organizer workspace.');
    }

    const count = Number(mlSnap.data().followersCount) || 0;
    txn.set(followerRef, { userId: uid, followedAtMs: Date.now() });
    txn.update(mlRef, { followersCount: count + 1, updatedAtMs: Date.now() });
  });
}

export async function unfollowWorkspace(masterLeagueId: string): Promise<void> {
  const uid = requireUid();
  const mlRef = doc(db, 'master_leagues', masterLeagueId);
  const followerRef = doc(db, 'master_leagues', masterLeagueId, 'followers', uid);

  await runTransaction(db, async (txn) => {
    const followerSnap = await txn.get(followerRef);
    if (!followerSnap.exists()) return;

    const mlSnap = await txn.get(mlRef);
    if (!mlSnap.exists()) throw new Error("We couldn't find that Master League.");

    const count = Number(mlSnap.data().followersCount) || 0;
    txn.delete(followerRef);
    txn.update(mlRef, { followersCount: Math.max(0, count - 1), updatedAtMs: Date.now() });
  });
}

export async function submitVerificationRequest(params: {
  masterLeagueId: string;
  attemptId: string;
  paymentId: string;
  receiptId: string;
  provider: string;
  note?: string;
  requestType: 'initial' | 'renewal';
}): Promise<void> {
  const uid = requireUid();
  const mlRef = doc(db, 'master_leagues', params.masterLeagueId);
  const mlSnap = await getDoc(mlRef);
  if (!mlSnap.exists()) throw new Error("We couldn't find that Master League.");
  if ((mlSnap.data().ownerId ?? mlSnap.data().ownerUid) !== uid) {
    throw new Error('Only the owner can submit organizer verification.');
  }

  const requestRef = doc(collection(db, 'master_league_verification_requests'));
  const now = Date.now();

  await setDoc(requestRef, {
    requestId: requestRef.id,
    masterLeagueId: params.masterLeagueId,
    ownerId: uid,
    status: 'pending',
    requestType: params.requestType,
    provider: params.provider,
    receiptId: params.receiptId,
    paymentId: params.paymentId,
    attemptId: params.attemptId,
    submittedAtMs: now,
    reviewedAtMs: 0,
    reviewedBy: '',
    note: (params.note ?? '').slice(0, 1000),
  });

  await updateDoc(mlRef, {
    verificationStatus: 'pending',
    verifiedBadge: false,
    verificationRequestId: requestRef.id,
    verificationReceiptId: params.receiptId,
    verificationPaymentId: params.paymentId,
    verificationProvider: params.provider,
    verificationRequestedAtMs: now,
    verificationApprovedAtMs: 0,
    verificationReviewedBy: '',
    verificationNote: (params.note ?? '').slice(0, 1000),
    verificationRequestType: params.requestType,
    updatedAtMs: now,
  });
}
