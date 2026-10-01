// lib/footballHub/footballFollowsRepository.ts
//
// Same Firestore collections the Flutter app's football_follows_repository.dart
// writes to (users/{uid}/football_followed_teams|football_followed_players),
// governed by the same firestore.rules already deployed -- a team/player
// followed from web shows up followed on mobile and vice versa.

import { collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, setDoc } from 'firebase/firestore';
import { auth, db } from '@/lib/firebase';

const PROVIDER_ID = 'api-football';

export interface FollowedFootballEntity {
  id: string;
  name: string;
  imageUrl: string | null;
}

function requireUid(): string {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid) throw new Error('Please sign in and try again.');
  return uid;
}

export async function isFollowingTeam(teamId: number): Promise<boolean> {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid) return false;
  const snap = await getDoc(doc(db, 'users', uid, 'football_followed_teams', String(teamId)));
  return snap.exists();
}

export async function isFollowingPlayer(playerId: number): Promise<boolean> {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid) return false;
  const snap = await getDoc(doc(db, 'users', uid, 'football_followed_players', String(playerId)));
  return snap.exists();
}

export async function followTeam(teamId: number, name: string, logoUrl?: string): Promise<void> {
  const uid = requireUid();
  await setDoc(doc(db, 'users', uid, 'football_followed_teams', String(teamId)), {
    teamId: String(teamId),
    teamName: name,
    ...(logoUrl ? { teamLogoUrl: logoUrl } : {}),
    provider: PROVIDER_ID,
    createdAtMs: Date.now(),
  });
}

export async function unfollowTeam(teamId: number): Promise<void> {
  const uid = requireUid();
  await deleteDoc(doc(db, 'users', uid, 'football_followed_teams', String(teamId)));
}

export async function followPlayer(playerId: number, name: string, photoUrl?: string): Promise<void> {
  const uid = requireUid();
  await setDoc(doc(db, 'users', uid, 'football_followed_players', String(playerId)), {
    playerId: String(playerId),
    playerName: name,
    ...(photoUrl ? { playerPhotoUrl: photoUrl } : {}),
    provider: PROVIDER_ID,
    createdAtMs: Date.now(),
  });
}

export async function unfollowPlayer(playerId: number): Promise<void> {
  const uid = requireUid();
  await deleteDoc(doc(db, 'users', uid, 'football_followed_players', String(playerId)));
}

export async function getFollowedTeams(): Promise<FollowedFootballEntity[]> {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid) return [];
  const q = query(collection(db, 'users', uid, 'football_followed_teams'), orderBy('createdAtMs', 'desc'));
  const snap = await getDocs(q);
  return snap.docs.map((d) => {
    const data = d.data();
    return { id: String(data.teamId ?? d.id), name: String(data.teamName ?? ''), imageUrl: data.teamLogoUrl ?? null };
  });
}

export async function getFollowedPlayers(): Promise<FollowedFootballEntity[]> {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid) return [];
  const q = query(collection(db, 'users', uid, 'football_followed_players'), orderBy('createdAtMs', 'desc'));
  const snap = await getDocs(q);
  return snap.docs.map((d) => {
    const data = d.data();
    return { id: String(data.playerId ?? d.id), name: String(data.playerName ?? ''), imageUrl: data.playerPhotoUrl ?? null };
  });
}
