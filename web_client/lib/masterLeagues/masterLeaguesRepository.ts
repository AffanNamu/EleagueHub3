import { 
  collection, doc, getDoc, getDocs, setDoc, updateDoc, 
  deleteDoc, runTransaction, serverTimestamp, writeBatch 
} from 'firebase/firestore';
import { db } from '@/lib/firebase';

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
  organizerProfile?: OrganizerProfile; // Client-side hydration mapping
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
