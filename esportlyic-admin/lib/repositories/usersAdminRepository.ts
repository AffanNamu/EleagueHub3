// lib/repositories/usersAdminRepository.ts

import 'server-only';

import { FieldValue } from 'firebase-admin/firestore';
import { adminAuth, adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { AdminUserProfile } from '@/types/user';

export interface UserSummary {
  userId: string;
  displayName: string;
  photoUrl: string;
  isVerified: boolean;
}

export async function getUserSummary(userId: string): Promise<UserSummary | null> {
  if (!userId) return null;

  const snap = await adminDb.collection('users').doc(userId).get();
  if (!snap.exists) return null;

  const data = snap.data() ?? {};
  const displayName =
    (typeof data.teamName === 'string' && data.teamName.trim()) ||
    (typeof data.displayName === 'string' && data.displayName.trim()) ||
    (typeof data.username === 'string' && data.username.trim()) ||
    'User';

  const photoUrl =
    (typeof data.profileImageUrl === 'string' && data.profileImageUrl) ||
    (typeof data.teamImageUrl === 'string' && data.teamImageUrl) ||
    (typeof data.photoUrl === 'string' && data.photoUrl) ||
    '';

  return { userId, displayName, photoUrl, isVerified: data.isVerified === true };
}

function looksLikeFirebaseUid(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 20;
}

async function getGlobalChatAdminUids(): Promise<Set<string>> {
  const snap = await adminDb.collection('app').doc('admins').get();
  if (!snap.exists) return new Set();
  const list = snap.data()?.globalChatAdmins;
  if (!Array.isArray(list)) return new Set();
  return new Set(list.filter(looksLikeFirebaseUid).map((v: string) => v.trim()));
}

export async function listUsers(params: { search?: string; limit?: number } = {}): Promise<UserSummary[]> {
  const { search, limit = 50 } = params;

  let query: FirebaseFirestore.Query = adminDb.collection('users');

  const term = search?.trim();
  if (term) {
    query = query.orderBy('teamName').startAt(term).endAt(`${term}\uf8ff`).limit(limit);
  } else {
    query = query.orderBy('createdAt', 'desc').limit(limit);
  }

  const snap = await query.get();
  return snap.docs.map((doc) => {
    const data = doc.data();
    const displayName =
      (typeof data.teamName === 'string' && data.teamName.trim()) ||
      (typeof data.username === 'string' && data.username.trim()) ||
      'User';
    return {
      userId: doc.id,
      displayName,
      photoUrl: (data.profileImageUrl as string) || (data.photoUrl as string) || '',
      isVerified: data.isVerified === true,
    };
  });
}

export async function getUserDetail(userId: string): Promise<AdminUserProfile | null> {
  const userRef = adminDb.collection('users').doc(userId);

  const [userSnap, chatModSnap, followersCountSnap, followingCountSnap, globalChatAdminUids, authRecord] =
    await Promise.all([
      userRef.get(),
      adminDb.collection('app').doc('chatModeration').collection('users').doc(userId).get(),
      userRef.collection('followers').count().get(),
      userRef.collection('following').count().get(),
      getGlobalChatAdminUids(),
      adminAuth.getUser(userId).catch(() => null),
    ]);

  if (!userSnap.exists) return null;

  const data = userSnap.data() ?? {};
  const verification = typeof data.verification === 'object' && data.verification !== null ? data.verification : {};
  const rawClaims = authRecord?.customClaims ?? {};

  return {
    userId,
    teamName: data.teamName ?? '',
    authProvider: data.authProvider ?? '',
    createdAtMs: typeof data.createdAt === 'number' ? data.createdAt : 0,
    updatedAtMs: typeof data.updatedAt === 'number' ? data.updatedAt : 0,
    shareId: data.shareId ?? '',
    username: data.username ?? '',
    usernameLower: data.usernameLower ?? '',
    photoUrl: data.photoUrl ?? '',
    profileImageUrl: data.profileImageUrl ?? '',
    teamImageUrl: data.teamImageUrl ?? '',
    isPremium: data.isPremium === true,
    premiumExpiresAtMs: typeof data.premiumExpiresAtMs === 'number' ? data.premiumExpiresAtMs : 0,
    isVerified: data.isVerified === true,
    verificationStatus: data.verificationStatus ?? '',
    plan: {
      activePlanId: data.activePlanId ?? '',
      activePlanDurationId: data.activePlanDurationId ?? '',
      planPurchasedAtMs: typeof data.planPurchasedAtMs === 'number' ? data.planPurchasedAtMs : 0,
      planExpiresAtMs: typeof data.planExpiresAtMs === 'number' ? data.planExpiresAtMs : 0,
      planReceiptId: data.planReceiptId ?? '',
      planProvider: data.planProvider ?? '',
    },
    badges: {
      greenVerified: verification.greenVerified === true,
      greenSource: verification.greenSource ?? null,
      greenExpiresAtMs: verification.greenExpiresAt?.toMillis?.() ?? null,
      organizerVerified: verification.organizerVerified === true,
      organizerSource: verification.organizerSource ?? null,
      organizerExpiresAtMs: verification.organizerExpiresAt?.toMillis?.() ?? null,
      staffVerified: verification.staffVerified === true,
      staffSource: verification.staffSource ?? null,
      staffExpiresAtMs: verification.staffExpiresAt?.toMillis?.() ?? null,
    },
    followersCount: followersCountSnap.data().count,
    followingCount: followingCountSnap.data().count,
    chatMuted: chatModSnap.exists && chatModSnap.data()?.allChatMuted === true,
    chatBanned: chatModSnap.exists && chatModSnap.data()?.allChatBanned === true,
    isGlobalChatAdmin: globalChatAdminUids.has(userId),
    claims: {
      organizerPro: rawClaims.organizerPro === true,
      organizerProPlan: typeof rawClaims.organizerProPlan === 'string' ? rawClaims.organizerProPlan : null,
      organizerProDuration: typeof rawClaims.organizerProDuration === 'string' ? rawClaims.organizerProDuration : null,
      organizerProExpiryMs: typeof rawClaims.organizerProExpiryMs === 'number' ? rawClaims.organizerProExpiryMs : null,
    },
  };
}

export class UserModerationError extends Error {}

export async function setChatModeration(params: {
  userId: string;
  muted: boolean;
  banned: boolean;
  updatedBy: string;
  updatedByEmail?: string | null;
}): Promise<void> {
  await adminDb
    .collection('app')
    .doc('chatModeration')
    .collection('users')
    .doc(params.userId)
    .set(
      {
        allChatMuted: params.muted,
        allChatBanned: params.banned,
        updatedAtMs: Date.now(),
        updatedBy: params.updatedBy,
      },
      { merge: true },
    );

  await recordAuditLog({
    actorUid: params.updatedBy,
    actorEmail: params.updatedByEmail,
    action: 'user.moderate',
    targetType: 'user',
    targetId: params.userId,
    summary: `Set chat status for ${params.userId}: muted=${params.muted}, banned=${params.banned}`,
  });
}

export async function setGlobalChatAdmin(params: {
  userId: string;
  isAdmin: boolean;
  updatedBy: string;
  updatedByEmail?: string | null;
}): Promise<void> {
  const ref = adminDb.collection('app').doc('admins');
  await ref.set(
    {
      globalChatAdmins: params.isAdmin
        ? FieldValue.arrayUnion(params.userId)
        : FieldValue.arrayRemove(params.userId),
    },
    { merge: true },
  );

  await recordAuditLog({
    actorUid: params.updatedBy,
    actorEmail: params.updatedByEmail,
    action: params.isAdmin ? 'user.global_chat_admin.grant' : 'user.global_chat_admin.revoke',
    targetType: 'user',
    targetId: params.userId,
    summary: `${params.isAdmin ? 'Granted' : 'Revoked'} Global Chat moderator status for ${params.userId}`,
  });
}
