import {
  collection, doc, getDoc, getDocs, setDoc, updateDoc,
  deleteDoc, runTransaction, serverTimestamp, writeBatch,
  query, where, orderBy, limit as fsLimit,
} from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { MasterLeague, masterLeagueFromDoc, isDiscoverable } from '@/types/masterLeague';

// ── TYPES ────────────────────────────────────────────────────────────────────

export interface OrganizerProfile {
  bannerUrl: string;
  logoUrl: string;
  bio: string;
  badge: string;
  socialLinks: Record<string, string>;
}

export interface MasterLeagueData {
  id: string;
  name: string;
  ownerId: string;
  ownerUid: string;
  createdAt: any;
  purchaseStatus: string;
  memberIds: string[];
  roles: Record<string, string>;
  staffShareIds: Record<string, string>;
  updatedAtMs: number;
  plan: string;
  bannerUrl: string;
  logoUrl: string;
  bio: string;
  badge: string;
  socialLinks: Record<string, string>;
  totalTournamentsCreated: number;
  totalParticipantsTeams: number;
  totalMatches: number;
  followersCount: number;
  createdViaAttemptId: string;
  sourcePaymentId: string;
  sourceReceiptId: string;
  initialCompetition: Record<string, any>;
  verificationStatus: string;
  verifiedBadge: boolean;
  verificationRequestId: string;
  verificationReceiptId: string;
  verificationPaymentId: string;
  verificationProvider: string;
  verificationRequestedAtMs: number;
  verificationApprovedAtMs: number;
  verificationExpiresAtMs: number;
  verificationReviewedBy: string;
  verificationNote: string;
  verificationRequestType: string;
  country: string;
  usernameLower: string;
}

export interface VerificationApplicationData {
  orgName: string;
  orgType: string;
  orgCountry: string;
  orgRegion: string;
  orgCity: string;
  contactEmail: string;
  contactPhone: string;
  website: string;
  socialLink: string;
  applicantFullName: string;
  applicantRole: string;
  orgDescription: string;
  competitionTypes: string;
  verificationReason: string;
  supportingLinks: string;
  logoUrl: string;
}

// ── CREATE ───────────────────────────────────────────────────────────────────

export async function createMasterLeagueWeb({
  name, compName, authUid
}: { name: string; compName: string; authUid: string }): Promise<string> {
  const mlId = `ml_${authUid}_1`; // For Basic Free Tier fallback mapping
  const ref = doc(db, 'master_leagues', mlId);
  const now = Date.now();

  // MUST CONTAIN EXACTLY 37 KEYS TO PASS FIRESTORE RULES
  const payload: Omit<MasterLeagueData, 'id' | 'organizerProfile'> = {
    name: name.trim(),
    ownerId: authUid,
    ownerUid: authUid,
    createdAt: serverTimestamp(),
    purchaseStatus: 'active',
    memberIds: [authUid],
    roles: { [authUid]: 'owner' },
    staffShareIds: {},
    updatedAtMs: now,
    plan: 'basic',
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
    initialCompetition: { name: compName.trim(), entryFee: 0, maxParticipants: 2, currency: 'NONE' },
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
    country: '', // Optional, backfilled later
    usernameLower: '',
  };

  await setDoc(ref, payload);
  return mlId;
}

// ── UPDATES ──────────────────────────────────────────────────────────────────

export async function updateOrganizerProfileWeb(mlId: string, profile: OrganizerProfile, authUid: string) {
  const ref = doc(db, 'master_leagues', mlId);
  
  // Enforce rule checking before update
  const snap = await getDoc(ref);
  if (!snap.exists() || snap.data().ownerId !== authUid) {
    throw new Error('Only the Master League owner can edit the organizer profile.');
  }

  await updateDoc(ref, {
    bannerUrl: profile.bannerUrl,
    logoUrl: profile.logoUrl,
    bio: profile.bio,
    badge: profile.badge,
    socialLinks: profile.socialLinks,
    updatedAtMs: Date.now(),
  });
}

export async function renameMasterLeagueWeb(mlId: string, newName: string) {
  const ref = doc(db, 'master_leagues', mlId);
  await updateDoc(ref, {
    name: newName.trim(),
    updatedAtMs: Date.now(),
  });
}

export async function deleteMasterLeagueWeb(mlId: string) {
  await deleteDoc(doc(db, 'master_leagues', mlId));
}

// ── FOLLOW ───────────────────────────────────────────────────────────────────

export async function toggleFollowWorkspaceWeb(mlId: string, authUid: string, isFollowing: boolean) {
  const followerRef = doc(db, 'master_leagues', mlId, 'followers', authUid);
  const mlRef = doc(db, 'master_leagues', mlId);

  const mlSnap = await getDoc(mlRef);
  if (!mlSnap.exists()) return;
  const currentCount = mlSnap.data().followersCount || 0;

  const batch = writeBatch(db);
  if (isFollowing) {
    batch.delete(followerRef);
    batch.update(mlRef, { followersCount: Math.max(0, currentCount - 1), updatedAtMs: Date.now() });
  } else {
    batch.set(followerRef, { userId: authUid, followedAtMs: Date.now() });
    batch.update(mlRef, { followersCount: currentCount + 1, updatedAtMs: Date.now() });
  }
  await batch.commit();
}

// ── ORGANIZER VERIFICATION ───────────────────────────────────────────────────

export async function submitVerificationApplicationWeb({
  mlId, authUid, attemptId, paymentId, receiptId, application
}: {
  mlId: string; authUid: string; attemptId: string; paymentId: string; receiptId: string; application: VerificationApplicationData;
}) {
  const requestRef = doc(collection(db, 'master_league_verification_requests'));
  const mlRef = doc(db, 'master_leagues', mlId);
  const payRef = doc(db, 'payments', paymentId);
  const attRef = doc(db, 'payment_attempts', attemptId);
  const now = Date.now();

  await runTransaction(db, async (txn) => {
    const mlDoc = await txn.get(mlRef);
    if (!mlDoc.exists() || mlDoc.data().ownerId !== authUid) throw new Error("Permission denied.");
    
    // 1. Create the verification request (STRICT PARITY: required fields)
    txn.set(requestRef, {
      requestId: requestRef.id,
      masterLeagueId: mlId,
      ownerId: authUid,
      status: 'pending',
      requestType: 'initial',
      provider: 'flutterwave', // Fallback web provider
      receiptId,
      paymentId,
      attemptId,
      submittedAtMs: now,
      reviewedAtMs: 0,
      reviewedBy: '',
      note: '',
      resubmittedAtMs: 0,
      ...application
    });

    // 2. Update the Master League status
    txn.update(mlRef, {
      verificationStatus: 'pending',
      verifiedBadge: false,
      verificationRequestId: requestRef.id,
      verificationReceiptId: receiptId,
      verificationPaymentId: paymentId,
      verificationProvider: 'flutterwave',
      verificationRequestedAtMs: now,
      verificationApprovedAtMs: 0,
      verificationExpiresAtMs: 0,
      verificationReviewedBy: '',
      verificationNote: '',
      verificationRequestType: 'initial',
      updatedAtMs: now,
    });

    // 3. Mark payment as fulfilled
    txn.update(payRef, { fulfilledVerificationRequestId: requestRef.id, fulfilledAtMs: now, updatedAtMs: now });
    
    // 4. Update attempt
    const attDoc = await txn.get(attRef);
    if (attDoc.exists()) {
      txn.set(attRef, { ...attDoc.data(), status: 'fulfilled', fulfilledVerificationRequestId: requestRef.id, receiptId, paymentId, updatedAtMs: now }, { merge: false });
    }
  });
}

// ── DISCIPLINE MANAGEMENT ────────────────────────────────────────────────────

export async function applyDisciplineActionWeb({
  mlId, authUid, targetUserId, targetName, targetRole, actionType, pointsDelta, reason
}: {
  mlId: string; authUid: string; targetUserId: string; targetName: string; targetRole: string;
  actionType: string; pointsDelta: number; reason: string;
}) {
  const actionRef = doc(collection(db, 'master_leagues', mlId, 'disciplineActions'));
  const modRef = doc(db, 'master_leagues', mlId, 'memberModeration', targetUserId);
  const now = Date.now();

  await runTransaction(db, async (txn) => {
    const modSnap = await txn.get(modRef);
    const modData = modSnap.exists() ? modSnap.data() : {};
    
    let nextPoints = (modData.points || 0) + pointsDelta;
    let nextWarnings = modData.warnings || 0;
    let nextMuted = modData.chatMuted || false;
    let nextBanned = modData.chatBanned || false;

    if (actionType === 'warning') nextWarnings += 1;
    if (actionType === 'organizer_chat_mute') nextMuted = true;
    if (actionType === 'organizer_chat_ban') { nextBanned = true; nextMuted = true; }
    if (actionType === 'organizer_chat_unmute') nextMuted = false;
    if (actionType === 'organizer_chat_unban') nextBanned = false;

    // Create Action Audit Log
    txn.set(actionRef, {
      id: actionRef.id,
      masterLeagueId: mlId,
      targetUserId,
      targetName,
      targetRole,
      actionType,
      pointsDelta,
      reason,
      createdBy: authUid,
      createdByName: 'Organizer',
      createdAtMs: now,
      active: true,
      reversedAtMs: 0,
      reversedBy: '',
      reversedByName: '',
      reversalReason: ''
    }, { merge: true });

    // Update User Moderation State
    txn.set(modRef, {
      userId: targetUserId,
      displayName: targetName,
      points: nextPoints,
      warnings: nextWarnings,
      chatMuted: nextMuted,
      chatBanned: nextBanned,
      updatedAtMs: now
    }, { merge: true });
  });
}

// ── ENTITLEMENTS / DISCOVERY ─────────────────────────────────────────────────
// Mirrors MasterLeagueEntitlementService.countOwnedWorkspaces() and
// MasterLeaguesRepositoryFirebase.discoverAllOrganizers()/
// discoverVerifiedOrganizers() — best-effort, matching Flutter's behavior
// of returning an empty/zero result on failure rather than throwing, since
// these back auto-loading discovery sections and plan-limit checks.

export async function countOwnedWorkspaces(uid: string): Promise<number> {
  try {
    const q = query(collection(db, 'master_leagues'), where('ownerId', '==', uid));
    const snap = await getDocs(q);
    return snap.size;
  } catch {
    return 0;
  }
}

export async function discoverAll(limit: number = 20): Promise<MasterLeague[]> {
  const q = query(collection(db, 'master_leagues'), orderBy('updatedAtMs', 'desc'), fsLimit(limit));
  const snap = await getDocs(q);
  return snap.docs
    .map((d) => masterLeagueFromDoc(d.id, d.data()))
    .filter(isDiscoverable);
}

export async function discoverVerified(limit: number = 12): Promise<MasterLeague[]> {
  const q = query(collection(db, 'master_leagues'), where('verifiedBadge', '==', true));
  const snap = await getDocs(q);
  const list = snap.docs.map((d) => masterLeagueFromDoc(d.id, d.data()));

  list.sort((a, b) => {
    if (b.followersCount !== a.followersCount) return b.followersCount - a.followersCount;
    return b.updatedAtMs - a.updatedAtMs;
  });

  return list.slice(0, limit);
}

// ── ORGANIZER VERIFICATION (simple payment-driven submission) ───────────────
// Mirrors MasterLeaguesRepositoryFirebase.submitVerificationRequest() /
// submitVerificationRenewalRequest() — combined into one function since the
// only difference between the two Dart methods is which eligibility check
// applies and which requestType gets written.

export async function submitVerificationRequest({
  masterLeagueId, attemptId, paymentId, receiptId, provider, note = '', requestType,
}: {
  masterLeagueId: string;
  attemptId: string;
  paymentId: string;
  receiptId: string;
  provider: string;
  note?: string;
  requestType: 'initial' | 'renewal';
}): Promise<void> {
  const uid = auth.currentUser?.uid;
  if (!uid) throw new Error('Please sign in and try again.');

  const mlId = masterLeagueId.trim();
  if (!mlId || !attemptId.trim() || !paymentId.trim() || !receiptId.trim()) {
    throw new Error(
      requestType === 'renewal'
        ? 'Renewal payment details are incomplete.'
        : 'Verification payment details are incomplete.',
    );
  }

  const requestRef = doc(collection(db, 'master_league_verification_requests'));
  const mlRef = doc(db, 'master_leagues', mlId);
  const payRef = doc(db, 'payments', paymentId);
  const now = Date.now();
  const safeNote = note.trim().slice(0, 1000);

  await runTransaction(db, async (txn) => {
    const mlDoc = await txn.get(mlRef);
    if (!mlDoc.exists()) throw new Error("We couldn't find that Master League.");

    const mlData = mlDoc.data();
    const ownerId = (mlData.ownerId || mlData.ownerUid || '').toString().trim();
    if (ownerId !== uid) {
      throw new Error(
        requestType === 'renewal'
          ? 'Only the owner can submit verification renewal.'
          : 'Only the owner can submit organizer verification.',
      );
    }

    const currentStatus = (mlData.verificationStatus || 'none').toString().trim().toLowerCase();
    const currentVerified = mlData.verifiedBadge === true;

    if (requestType === 'initial') {
      if (currentVerified || currentStatus === 'approved') {
        throw new Error('This organizer is already verified.');
      }
      if (currentStatus === 'pending') {
        throw new Error('A verification request is already pending review.');
      }
    } else {
      const expiresAtMs = Number(mlData.verificationExpiresAtMs) || 0;
      const expired = expiresAtMs > 0 && expiresAtMs <= now;
      const canRenew = currentVerified || expired;
      if (!canRenew) {
        throw new Error('This organizer is not eligible for verification renewal.');
      }
      const currentRequestType = (mlData.verificationRequestType || 'initial').toString().trim().toLowerCase();
      if (currentStatus === 'pending' && currentRequestType === 'renewal') {
        throw new Error('A verification renewal request is already pending review.');
      }
    }

    txn.set(requestRef, {
      requestId: requestRef.id,
      masterLeagueId: mlId,
      ownerId: uid,
      status: 'pending',
      requestType,
      provider,
      receiptId,
      paymentId,
      attemptId,
      submittedAtMs: now,
      reviewedAtMs: 0,
      reviewedBy: '',
      note: safeNote,
    });

    txn.update(mlRef, {
      verificationStatus: 'pending',
      verifiedBadge: false,
      verificationRequestId: requestRef.id,
      verificationReceiptId: receiptId,
      verificationPaymentId: paymentId,
      verificationProvider: provider,
      verificationRequestedAtMs: now,
      verificationApprovedAtMs: 0,
      verificationExpiresAtMs: 0,
      verificationReviewedBy: '',
      verificationNote: safeNote,
      verificationRequestType: requestType,
      updatedAtMs: now,
    });

    txn.update(payRef, { fulfilledVerificationRequestId: requestRef.id, fulfilledAtMs: now, updatedAtMs: now });
  });
}
