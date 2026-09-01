import { collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, runTransaction, writeBatch, query, limit, orderBy } from 'firebase/firestore';
import { db } from '@/lib/firebase';

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
