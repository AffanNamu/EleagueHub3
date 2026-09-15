import { collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, runTransaction, writeBatch, query, limit, orderBy, Timestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { auth } from '@/lib/firebase';
import { v4 as uuidv4 } from 'uuid';

// ── TYPES ────────────────────────────────────────────────────────────────────

export interface TeamProfileData {
  userId: string;
  game: string;
  favoriteClub: string;
  favoritePlayer: string;
  bio: string;
  bannerImageUrl: string;
  themeColor: string;
  visibility: string;
  updatedAtMs: number;
}

export interface UserStats {
  wins: number;
  draws: number;
  losses: number;
  goalsScored: number;
  goalsConceded: number;
  trophies: number;
  followersCount: number;
  followingCount: number;
  competitionsJoined: number;
  matchesPlayed: number;
  winPercentage: number;
}

export interface Trophy {
  id: string;
  leagueId: string;
  leagueName: string;
  position: number;
  season: string;
  createdAtMs: number;
}

export interface RecentMatch {
  id: string;
  leagueId: string;
  leagueName: string;
  opponentName: string;
  result: 'W' | 'D' | 'L';
  goalsFor: number;
  goalsAgainst: number;
  playedAtMs: number;
}

export interface SquadPlayerSlot {
  playerId: string;
  name: string;
  position: string;
  x: number;
  y: number;
  isStarting: boolean;
  shirtNumber: number;
  slotIndex: number;
  photoUrl: string;
}

export interface SquadData {
  gameId: string;
  formation: string;
  players: SquadPlayerSlot[];
  managerName: string;
  captainPlayerId: string;
  viceCaptainPlayerId: string;
  teamStrength: number;
  updatedAtMs: number;
  /**
   * A real photo of the user's actual squad/team (distinct from the
   * per-player photoUrl on SquadPlayerSlot). Mirrors
   * lib/features/profile/models/squad.dart's `squadPhotoUrl`. Empty
   * string = none uploaded.
   */
  squadPhotoUrl: string;
}

// ── TEAM PROFILE ─────────────────────────────────────────────────────────────

export async function fetchTeamProfileWeb(userId: string): Promise<TeamProfileData> {
  const snap = await getDoc(doc(db, 'users', userId, 'team_profile', 'profile'));
  if (snap.exists()) return { userId, ...snap.data() } as TeamProfileData;
  return { userId, game: 'local_football', favoriteClub: '', favoritePlayer: '', bio: '', bannerImageUrl: '', themeColor: '', visibility: 'public', updatedAtMs: 0 };
}

export async function updateTeamBannerWeb(userId: string, bannerImageUrl: string) {
  const ref = doc(db, 'users', userId, 'team_profile', 'profile');
  const snap = await getDoc(ref);
  const now = Date.now();
  if (!snap.exists()) {
    await setDoc(ref, { game: 'local_football', favoriteClub: '', favoritePlayer: '', bio: '', bannerImageUrl, themeColor: '', visibility: 'public', updatedAtMs: now });
  } else {
    await updateDoc(ref, { bannerImageUrl, updatedAtMs: now });
  }
}

export async function updateTeamBioWeb(userId: string, bio: string) {
  const ref = doc(db, 'users', userId, 'team_profile', 'profile');
  const snap = await getDoc(ref);
  const now = Date.now();
  if (!snap.exists()) {
    await setDoc(ref, { game: 'local_football', favoriteClub: '', favoritePlayer: '', bio, bannerImageUrl: '', themeColor: '', visibility: 'public', updatedAtMs: now });
  } else {
    await updateDoc(ref, { bio, updatedAtMs: now });
  }
}

// ── SQUADS ───────────────────────────────────────────────────────────────────

export async function saveSquadWeb(userId: string, squad: SquadData) {
  await setDoc(doc(db, 'users', userId, 'squads', squad.gameId), {
    ...squad,
    updatedAtMs: Date.now()
  }, { merge: true });
}

/**
 * Updates ONLY the real squad/team photo for [gameId]. Fetches the
 * existing squad first (rather than a bare updateDoc that could target a
 * doc that doesn't exist yet) mirroring
 * TeamProfileRepository.updateSquadPhoto on mobile.
 */
export async function updateSquadPhotoWeb(userId: string, gameId: string, squadPhotoUrl: string) {
  const ref = doc(db, 'users', userId, 'squads', gameId);
  const snap = await getDoc(ref);
  const now = Date.now();
  if (!snap.exists()) {
    await setDoc(ref, {
      gameId,
      formation: '4-3-3',
      players: [],
      managerName: '',
      captainPlayerId: '',
      viceCaptainPlayerId: '',
      teamStrength: 0,
      updatedAtMs: now,
      squadPhotoUrl,
    });
  } else {
    await updateDoc(ref, { squadPhotoUrl, updatedAtMs: now });
  }
}

// ── FOLLOW / BLOCK TRANSACTIONS ──────────────────────────────────────────────

export async function toggleFollowWeb(authUid: string, targetUid: string, isCurrentlyFollowing: boolean) {
  if (!authUid || !targetUid || authUid === targetUid) throw new Error('Invalid target');
  
  const followerRef = doc(db, 'users', targetUid, 'followers', authUid);
  const followingRef = doc(db, 'users', authUid, 'following', targetUid);
  const targetStatsRef = doc(db, 'users', targetUid, 'stats', 'summary');
  const selfStatsRef = doc(db, 'users', authUid, 'stats', 'summary');

  await runTransaction(db, async (txn) => {
    const existing = await txn.get(followerRef);

    if (isCurrentlyFollowing && existing.exists()) {
      txn.delete(followerRef);
      txn.delete(followingRef);
      const tSnap = await txn.get(targetStatsRef);
      const sSnap = await txn.get(selfStatsRef);
      txn.set(targetStatsRef, { followersCount: Math.max(0, (tSnap.data()?.followersCount || 0) - 1) }, { merge: true });
      txn.set(selfStatsRef, { followingCount: Math.max(0, (sSnap.data()?.followingCount || 0) - 1) }, { merge: true });
    } else if (!isCurrentlyFollowing && !existing.exists()) {
      const now = Date.now();
      txn.set(followerRef, { userId: authUid, followedAtMs: now });
      txn.set(followingRef, { userId: targetUid, followedAtMs: now });
      const tSnap = await txn.get(targetStatsRef);
      const sSnap = await txn.get(selfStatsRef);
      txn.set(targetStatsRef, { followersCount: (tSnap.data()?.followersCount || 0) + 1 }, { merge: true });
      txn.set(selfStatsRef, { followingCount: (sSnap.data()?.followingCount || 0) + 1 }, { merge: true });
    }
  });
}

export async function toggleBlockWeb(authUid: string, targetUid: string, isCurrentlyBlocked: boolean) {
  if (!authUid || !targetUid || authUid === targetUid) throw new Error('Invalid target');
  const batch = writeBatch(db);
  const uBlockedRef = doc(db, 'users', authUid, 'blocked_users', targetUid);
  const tBlockedByRef = doc(db, 'users', targetUid, 'blocked_by', authUid);

  if (isCurrentlyBlocked) {
    batch.delete(uBlockedRef);
    batch.delete(tBlockedByRef);
  } else {
    const now = Date.now();
    batch.set(uBlockedRef, { userId: targetUid, blockedAtMs: now });
    batch.set(tBlockedByRef, { userId: authUid, blockedAtMs: now });
  }
  await batch.commit();
}

export async function checkRelationshipStatusWeb(authUid: string, targetUid: string) {
  if (!authUid || !targetUid) return { following: false, blocked: false };
  const followingSnap = await getDoc(doc(db, 'users', targetUid, 'followers', authUid));
  const blockedSnap = await getDoc(doc(db, 'users', authUid, 'blocked_users', targetUid));
  return {
    following: followingSnap.exists(),
    blocked: blockedSnap.exists(),
  };
}

// ── GAME LABELS ──────────────────────────────────────────────────────────────
// Mirrors lib/features/profile/models/game_id.dart's GameId.label() exactly —
// same doc-id strings, same display strings.

export const GAME_ID_LABELS: Record<string, string> = {
  local_football: 'Local Football',
  efootball: 'eFootball',
  ea_fc: 'EA SPORTS FC',
  ea_fc_mobile: 'EA SPORTS FC Mobile',
  dream_league_soccer: 'Dream League Soccer',
  total_football: 'Total Football',
};

export function gameIdLabel(id: string): string {
  return GAME_ID_LABELS[id] || GAME_ID_LABELS.local_football;
}

// ── DISPLAY GAME ID RESOLUTION ────────────────────────────────────────────────
// Mirrors TeamProfileRepository.resolveDisplayGameIds() on mobile
// (lib/features/profile/data/team_profile_repository.dart). team_profile's
// own `game` field is written once at onboarding and never updated when the
// user later builds/switches squads via the Squad screen, so it goes stale
// the moment someone plays a category other than whatever onboarding set —
// this resolves the category actually being shown from the squads
// collection instead, exactly like the squad preview already does.

const KNOWN_GAME_IDS = new Set(Object.keys(GAME_ID_LABELS));
const DEFAULT_GAME_ID = 'local_football';

async function fetchSquadGameIdsWeb(userId: string): Promise<string[]> {
  const snap = await getDocs(collection(db, 'users', userId, 'squads'));
  return snap.docs.map((d) => d.id);
}

/** The game the user actually chose during onboarding (users/{uid}.preferredGameId). */
async function fetchPreferredGameIdWeb(userId: string): Promise<string> {
  const snap = await getDoc(doc(db, 'users', userId));
  const raw = (snap.exists() ? (snap.data().preferredGameId as string | undefined) : undefined)?.trim() ?? '';
  return KNOWN_GAME_IDS.has(raw) ? raw : DEFAULT_GAME_ID;
}

/**
 * The game IDs to actually display for this user: their built squads if any
 * exist, otherwise a single-item list with their onboarding choice — never
 * a hardcoded Local Football unless that's genuinely what they picked or
 * nothing was ever recorded.
 */
export async function resolveDisplayGameIdsWeb(userId: string): Promise<string[]> {
  const ids = await fetchSquadGameIdsWeb(userId);
  if (ids.length > 0) return ids;
  return [await fetchPreferredGameIdWeb(userId)];
}

// ── VERIFICATION BADGES ───────────────────────────────────────────────────────
// Mirrors lib/features/verification/domain/badge_model.dart's VerificationBadges
// (isGreenActive/isOrganizerActive/isStaffActive — expiry-aware) plus the
// legacy/general "verified" flag mobile computes in UserProfile.verifiedActive
// (lib/features/auth/models/user_profile.dart). These are 4 DISTINCT badges,
// not 2 — a doc can carry the legacy blue tick and the newer green badge
// independently of each other.

export interface ResolvedVerificationBadges {
  /** Legacy/general blue tick — isVerified / verifiedBadge / verificationStatus==='approved'. */
  verified: boolean;
  /** Gold organizer badge — verification.organizerVerified, or the legacy flat isVerifiedOrganizer field. */
  organizer: boolean;
  /** Purple staff/ambassador badge — verification.staffVerified. */
  staff: boolean;
  /** Green verified badge (distinct from the legacy blue tick) — verification.greenVerified. */
  green: boolean;
}

function isExpiryStillActive(expiresAt: unknown): boolean {
  if (expiresAt == null) return true; // no expiry = never expires
  // Matches Dart's `if (verificationExpiresAtMs <= 0) return true` — a
  // zero/negative ms value means "unset", not "already expired".
  if (typeof expiresAt === 'number') return expiresAt <= 0 || expiresAt > Date.now();
  if (expiresAt instanceof Timestamp) return expiresAt.toMillis() > Date.now();
  return true;
}

export function resolveVerificationBadges(data: Record<string, unknown> | undefined | null): ResolvedVerificationBadges {
  const v = (data && typeof data === 'object' ? (data.verification as Record<string, unknown> | undefined) : undefined) || {};

  const staff = v.staffVerified === true && isExpiryStillActive(v.staffExpiresAt);
  const organizer =
    (v.organizerVerified === true && isExpiryStillActive(v.organizerExpiresAt)) ||
    data?.isVerifiedOrganizer === true;
  const green = v.greenVerified === true && isExpiryStillActive(v.greenExpiresAt);

  // Mirrors UserProfile.verifiedActive: the merged isVerified/verifiedBadge/
  // verificationStatus flag is gated by ONE shared expiry
  // (verificationExpiresAtMs, falling back to the older verifiedExpiresAtMs
  // field name) — previously missing here, so an expired legacy-verified
  // user kept showing the blue tick forever.
  const verifiedFlag =
    data?.isVerified === true ||
    data?.verifiedBadge === true ||
    (typeof data?.verificationStatus === 'string' && data.verificationStatus.trim().toLowerCase() === 'approved');
  const verified = verifiedFlag && isExpiryStillActive(data?.verificationExpiresAtMs ?? data?.verifiedExpiresAtMs);

  return { staff, organizer, green, verified };
}

// ── USER REPORTS ─────────────────────────────────────────────────────────────
// Mirrors lib/features/moderation/data/report_repository.dart's
// ReportRepository.submitReport() exactly — same collection, same field
// shape — so reports filed from web land in the same admin moderation queue
// as reports filed from the mobile app.

export const USER_REPORT_REASONS = ['spam', 'harassment', 'impersonation', 'cheating', 'other'] as const;
export type UserReportReason = (typeof USER_REPORT_REASONS)[number];

export function userReportReasonLabel(reason: string): string {
  switch (reason) {
    case 'spam': return 'Spam';
    case 'harassment': return 'Harassment';
    case 'impersonation': return 'Impersonation';
    case 'cheating': return 'Cheating';
    default: return 'Other';
  }
}

export async function submitReportWeb(params: {
  targetUserId: string;
  reason: string;
  details?: string;
}) {
  const reporterId = auth.currentUser?.uid.trim() || '';
  if (!reporterId) throw new Error('Please sign in and try again.');
  const target = params.targetUserId.trim();
  if (!target || target === reporterId) throw new Error('Invalid report target.');

  const id = uuidv4();
  const now = Date.now();

  await setDoc(doc(db, 'reports', id), {
    reportId: id,
    reporterId,
    targetUserId: target,
    reason: params.reason,
    details: (params.details || '').trim(),
    status: 'pending',
    createdAtMs: now,
    reviewedAtMs: 0,
    reviewedBy: '',
  });
}

// ── MATCH STATS & TROPHIES (Admin Operations) ────────────────────────────────

export async function recordMatchResultWeb(payload: {
  leagueId: string; leagueName: string; matchId: string; 
  ownerCandidateId: string; opponentName: string; 
  goalsFor: number; goalsAgainst: number; playedAtMs: number;
}) {
  const uid = payload.ownerCandidateId.trim();
  if (uid.length <= 20) return; // Not a firebase uid

  const matchRef = doc(db, 'users', uid, 'recent_matches', payload.matchId);
  const statsRef = doc(db, 'users', uid, 'stats', 'summary');
  const newResult = payload.goalsFor > payload.goalsAgainst ? 'W' : (payload.goalsFor === payload.goalsAgainst ? 'D' : 'L');

  try {
    await runTransaction(db, async (txn) => {
      const matchSnap = await txn.get(matchRef);
      const statsSnap = await txn.get(statsRef);
      const stats = statsSnap.data() || { wins: 0, draws: 0, losses: 0, goalsScored: 0, goalsConceded: 0 };

      let { wins, draws, losses, goalsScored: gf, goalsConceded: ga } = stats;

      if (matchSnap.exists()) {
        const old = matchSnap.data();
        if (old.result === 'W') wins = Math.max(0, wins - 1);
        if (old.result === 'D') draws = Math.max(0, draws - 1);
        if (old.result === 'L') losses = Math.max(0, losses - 1);
        gf = Math.max(0, gf - (old.goalsFor || 0));
        ga = Math.max(0, ga - (old.goalsAgainst || 0));
      }

      if (newResult === 'W') wins++;
      if (newResult === 'D') draws++;
      if (newResult === 'L') losses++;
      gf += payload.goalsFor;
      ga += payload.goalsAgainst;

      txn.set(matchRef, {
        leagueId: payload.leagueId, leagueName: payload.leagueName,
        opponentName: payload.opponentName, result: newResult,
        goalsFor: payload.goalsFor, goalsAgainst: payload.goalsAgainst,
        playedAtMs: payload.playedAtMs
      });

      txn.set(statsRef, { wins, draws, losses, goalsScored: gf, goalsConceded: ga }, { merge: true });
    });
  } catch (e) {
    console.warn('MatchStatsService failed (non-fatal)', e);
  }
}
