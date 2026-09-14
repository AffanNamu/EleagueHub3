import {
  collection, doc, documentId, getDoc, getDocs, setDoc, updateDoc,
  deleteDoc, deleteField, arrayRemove, runTransaction, serverTimestamp, writeBatch,
  query, where, orderBy, limit as fsLimit,
} from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';
import { MasterLeague, masterLeagueFromDoc, isDiscoverable } from '@/types/masterLeague';
import {
  MasterLeagueStaffRoleId,
  staffRoleFromStorageValue,
  MASTER_LEAGUE_STAFF_ROLES,
} from '@/lib/masterLeagues/roles';
import { resolveTeamParticipant } from '@/lib/services/userProfileRepository';

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

// ── STAFF MANAGEMENT ─────────────────────────────────────────────────────────
// Mirrors MasterLeaguesRepositoryFirebase.addStaffByShortId/removeStaff/
// setStaffCompetitionScope (master_leagues_repository_firebase.dart). Web
// previously had no staff management at all — mobile's add-staff dialog was
// the only entry point.

export interface MasterLeagueStaffMember {
  userId: string;
  displayName: string;
  photoUrl: string;
  role: MasterLeagueStaffRoleId;
  competitionScope: string[]; // empty = unrestricted (all competitions)
}

/**
 * Lightweight, append-only audit trail for staff CRUD — mirrors the
 * disciplineActions pattern (create-only, no update/delete) and the
 * matching _staffAuditEntry() helper in master_leagues_repository_firebase.dart.
 */
function staffAuditEntry({
  entryId, mlId, action, performedBy, targetUserId, targetRole = '', details = '',
}: {
  entryId: string; mlId: string; action: string; performedBy: string;
  targetUserId: string; targetRole?: string; details?: string;
}) {
  return {
    id: entryId,
    masterLeagueId: mlId,
    action,
    performedBy,
    targetUserId,
    targetRole,
    details,
    performedAtMs: Date.now(),
  };
}

/**
 * Adds a staff member by their short id (or full uid) and role.
 * Owner-only — enforced both here (pre-check) and by firestore.rules.
 */
export async function addStaffByShortIdWeb({
  mlId, authUid, shortId, role,
}: {
  mlId: string; authUid: string; shortId: string; role: MasterLeagueStaffRoleId;
}): Promise<void> {
  const shareId = shortId.trim();
  const resolvedRole = staffRoleFromStorageValue(role);
  if (!resolvedRole || !MASTER_LEAGUE_STAFF_ROLES[resolvedRole].isAssignable) {
    throw new Error('Invalid staff role selected.');
  }

  const participant = await resolveTeamParticipant(shareId);
  if (!participant) {
    throw new Error("We couldn't find a user with that short id.");
  }
  const targetUid = participant.userId;

  const mlRef = doc(db, 'master_leagues', mlId);

  await runTransaction(db, async (txn) => {
    const mlSnap = await txn.get(mlRef);
    if (!mlSnap.exists()) throw new Error("We couldn't find that Master League.");
    const data = mlSnap.data();

    if ((data.ownerId ?? '') !== authUid) {
      throw new Error('Only the Master League owner can add staff.');
    }
    if (targetUid === authUid) {
      throw new Error('The owner is already part of this Master League.');
    }

    const memberIds: string[] = Array.isArray(data.memberIds) ? [...data.memberIds] : [];
    if (!memberIds.includes(targetUid)) memberIds.push(targetUid);

    const roles: Record<string, string> = { ...(data.roles ?? {}) };
    roles[targetUid] = resolvedRole;

    txn.update(mlRef, {
      memberIds,
      roles,
      updatedAtMs: Date.now(),
    });

    const auditRef = doc(collection(db, 'master_leagues', mlId, 'staffAuditLog'));
    txn.set(auditRef, staffAuditEntry({
      entryId: auditRef.id,
      mlId,
      action: 'staff_added',
      performedBy: authUid,
      targetUserId: targetUid,
      targetRole: resolvedRole,
    }));
  });
}

/**
 * Removes a staff member's role, membership, and competition scope.
 * Owner-only. Never removes the owner.
 */
export async function removeStaffWeb({
  mlId, authUid, targetUid,
}: {
  mlId: string; authUid: string; targetUid: string;
}): Promise<void> {
  const target = targetUid.trim();
  const mlRef = doc(db, 'master_leagues', mlId);

  const mlSnap = await getDoc(mlRef);
  if (!mlSnap.exists()) throw new Error("We couldn't find that Master League.");
  const data = mlSnap.data();

  if ((data.ownerId ?? '') !== authUid) {
    throw new Error('Only the Master League owner can remove staff.');
  }
  if (target === (data.ownerId ?? '')) {
    throw new Error('The workspace owner cannot be removed as staff.');
  }

  const previousRole = String((data.roles ?? {})[target] ?? '').trim();

  const batch = writeBatch(db);
  batch.update(mlRef, {
    [`roles.${target}`]: deleteField(),
    [`staffScopes.${target}`]: deleteField(),
    memberIds: arrayRemove(target),
    updatedAtMs: Date.now(),
  });

  const auditRef = doc(collection(db, 'master_leagues', mlId, 'staffAuditLog'));
  batch.set(auditRef, staffAuditEntry({
    entryId: auditRef.id,
    mlId,
    action: 'staff_removed',
    performedBy: authUid,
    targetUserId: target,
    targetRole: previousRole,
  }));

  await batch.commit();
}

/**
 * Restricts (or clears the restriction on) which competitions a staff
 * member may act on. An empty leagueIds array clears the scope.
 * Owner-only.
 */
export async function setStaffCompetitionScopeWeb({
  mlId, authUid, targetUid, leagueIds,
}: {
  mlId: string; authUid: string; targetUid: string; leagueIds: string[];
}): Promise<void> {
  const target = targetUid.trim();
  const mlRef = doc(db, 'master_leagues', mlId);

  const mlSnap = await getDoc(mlRef);
  if (!mlSnap.exists()) throw new Error("We couldn't find that Master League.");
  const data = mlSnap.data();

  if ((data.ownerId ?? '') !== authUid) {
    throw new Error('Only the Master League owner can change staff access.');
  }
  if (target === (data.ownerId ?? '')) {
    throw new Error('The workspace owner always has full access.');
  }
  const roles: Record<string, string> = data.roles ?? {};
  if (!(target in roles)) {
    throw new Error('That user is not a staff member of this workspace.');
  }

  const cleanIds = Array.from(new Set(leagueIds.map((id) => id.trim()).filter(Boolean)));
  const targetRole = String(roles[target] ?? '').trim();

  const batch = writeBatch(db);
  batch.update(mlRef, {
    [`staffScopes.${target}`]: cleanIds.length === 0 ? deleteField() : cleanIds,
    updatedAtMs: Date.now(),
  });

  const auditRef = doc(collection(db, 'master_leagues', mlId, 'staffAuditLog'));
  batch.set(auditRef, staffAuditEntry({
    entryId: auditRef.id,
    mlId,
    action: 'scope_changed',
    performedBy: authUid,
    targetUserId: target,
    targetRole,
    details: cleanIds.length === 0 ? 'all competitions' : cleanIds.join(','),
  }));

  await batch.commit();
}

/**
 * Lists the owner plus every staff member, resolved with display names —
 * mirrors _OrganizerMemberPickerSheet's user-loading logic (chunked
 * documentId() whereIn lookups) plus the owner row.
 */
export async function listStaffWeb(mlId: string): Promise<MasterLeagueStaffMember[]> {
  const mlSnap = await getDoc(doc(db, 'master_leagues', mlId));
  if (!mlSnap.exists()) return [];
  const data = mlSnap.data();

  const ownerId = String(data.ownerId ?? '').trim();
  const roles: Record<string, string> = data.roles ?? {};
  const staffScopes: Record<string, string[]> = data.staffScopes ?? {};

  const uids = Array.from(
    new Set([ownerId, ...Object.keys(roles)].map((u) => u.trim()).filter(Boolean)),
  );
  if (uids.length === 0) return [];

  const profiles = new Map<string, { displayName: string; photoUrl: string }>();
  const chunkSize = 10;
  for (let i = 0; i < uids.length; i += chunkSize) {
    const chunk = uids.slice(i, i + chunkSize);
    const q = query(collection(db, 'users'), where(documentId(), 'in', chunk));
    const snap = await getDocs(q);
    snap.docs.forEach((d) => {
      const u = d.data();
      const displayName = String(u.teamName ?? u.displayName ?? u.name ?? u.username ?? '').trim();
      const photoUrl = String(u.photoUrl ?? u.profileImageUrl ?? u.teamImageUrl ?? '').trim();
      profiles.set(d.id, { displayName, photoUrl });
    });
  }

  return uids
    .map((uid): MasterLeagueStaffMember | null => {
      const role = uid === ownerId ? 'owner' : staffRoleFromStorageValue(roles[uid]);
      if (!role) return null;
      const profile = profiles.get(uid);
      return {
        userId: uid,
        displayName: profile?.displayName ?? '',
        photoUrl: profile?.photoUrl ?? '',
        role,
        competitionScope: staffScopes[uid] ?? [],
      };
    })
    .filter((m): m is MasterLeagueStaffMember => m !== null);
}

export interface MasterLeagueStaffAuditEntry {
  id: string;
  action: string;
  performedBy: string;
  targetUserId: string;
  targetRole: string;
  details: string;
  performedAtMs: number;
}

/** Recent staff CRUD activity, newest first. Owner-only per firestore.rules. */
export async function listStaffAuditLogWeb(
  mlId: string,
  max: number = 20,
): Promise<MasterLeagueStaffAuditEntry[]> {
  const q = query(
    collection(db, 'master_leagues', mlId, 'staffAuditLog'),
    orderBy('performedAtMs', 'desc'),
    fsLimit(max),
  );
  const snap = await getDocs(q);
  return snap.docs.map((d) => {
    const data = d.data();
    return {
      id: d.id,
      action: String(data.action ?? '').trim(),
      performedBy: String(data.performedBy ?? '').trim(),
      targetUserId: String(data.targetUserId ?? '').trim(),
      targetRole: String(data.targetRole ?? '').trim(),
      details: String(data.details ?? '').trim(),
      performedAtMs: Number(data.performedAtMs ?? 0),
    };
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

/** Mirrors discoverRecentActiveOrganizers() — over-fetches 3x then trims
 * after the isDiscoverable filter, so a page of mostly-inactive/unnamed
 * workspaces doesn't return fewer than `limit` results. */
export async function discoverRecentActive(limit: number = 12): Promise<MasterLeague[]> {
  const q = query(collection(db, 'master_leagues'), orderBy('updatedAtMs', 'desc'), fsLimit(limit * 3));
  const snap = await getDocs(q);
  return snap.docs
    .map((d) => masterLeagueFromDoc(d.id, d.data()))
    .filter(isDiscoverable)
    .slice(0, limit);
}

/** Mirrors discoverNearbyOrganizers() — "Organizers Near You", filtered by
 * the same resolved country code Search's "Teams Near You" uses. Fails
 * closed to an empty list (never throws) since this backs an
 * auto-loading, best-effort discovery section. */
export async function discoverNearby(countryCode: string, limit: number = 12): Promise<MasterLeague[]> {
  const cc = countryCode.trim().toUpperCase();
  if (!cc) return [];

  try {
    const q = query(
      collection(db, 'master_leagues'),
      where('country', '==', cc),
      orderBy('updatedAtMs', 'desc'),
      fsLimit(limit),
    );
    const snap = await getDocs(q);
    return snap.docs
      .map((d) => masterLeagueFromDoc(d.id, d.data()))
      .filter(isDiscoverable);
  } catch (err) {
    console.error('[masterLeaguesRepository] discoverNearby failed:', err);
    return [];
  }
}

/** Mirrors discoverFeaturedOrganizers() — reads the admin-curated
 * app/featured_organizers doc's masterLeagueIds array, chunk-fetches
 * those specific workspaces (Firestore's `in` operator caps at 10 ids
 * per query), sorts by recency, and falls back to discoverAll() if the
 * list is empty or the fetch fails — same as the Dart repo. */
export async function discoverFeatured(limit: number = 8): Promise<MasterLeague[]> {
  try {
    const featuredSnap = await getDoc(doc(db, 'app', 'featured_organizers'));
    const idsRaw = featuredSnap.data()?.masterLeagueIds;
    const ids: string[] = Array.isArray(idsRaw)
      ? idsRaw.map((v) => String(v ?? '').trim()).filter((s) => s.length > 0)
      : [];

    if (ids.length > 0) {
      const out: MasterLeague[] = [];
      const chunkSize = 10;
      for (let i = 0; i < ids.length; i += chunkSize) {
        const chunk = ids.slice(i, i + chunkSize);
        try {
          const snap = await getDocs(query(collection(db, 'master_leagues'), where(documentId(), 'in', chunk)));
          out.push(...snap.docs.map((d) => masterLeagueFromDoc(d.id, d.data())));
        } catch (err) {
          console.error('[masterLeaguesRepository] discoverFeatured chunk failed:', err);
        }
      }

      if (out.length > 0) {
        out.sort((a, b) => b.updatedAtMs - a.updatedAtMs);
        return out.slice(0, limit);
      }
    }

    return await discoverAll(limit);
  } catch (err) {
    console.error('[masterLeaguesRepository] discoverFeatured failed:', err);
    try {
      return await discoverAll(limit);
    } catch {
      return [];
    }
  }
}

/** Mirrors fetchWorkspaceByUsername() — resolves an @handle to its
 * reserved organizer_usernames doc, then fetches that workspace. Returns
 * null (never throws) for "not found" and any failure, matching the
 * Dart repo's best-effort behavior for this search-box lookup. */
export async function fetchWorkspaceByUsername(username: string): Promise<MasterLeague | null> {
  try {
    let normalized = username.trim().toLowerCase();
    if (normalized.startsWith('@')) normalized = normalized.slice(1);
    if (!normalized) return null;

    const reservationSnap = await getDoc(doc(db, 'organizer_usernames', normalized));
    if (!reservationSnap.exists()) return null;

    const targetId = String(reservationSnap.data()?.masterLeagueId ?? '').trim();
    if (!targetId) return null;

    const mlSnap = await getDoc(doc(db, 'master_leagues', targetId));
    if (!mlSnap.exists()) return null;

    return masterLeagueFromDoc(mlSnap.id, mlSnap.data());
  } catch (err) {
    console.error('[masterLeaguesRepository] fetchWorkspaceByUsername failed:', err);
    return null;
  }
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
