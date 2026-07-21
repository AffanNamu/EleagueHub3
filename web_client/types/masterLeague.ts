export type MasterLeaguePlanId = 'basic' | 'pro' | 'elite';
export type PlanDurationId = '3mo' | '6mo' | 'yearly';

export interface MasterLeaguePlanDef {
  id: MasterLeaguePlanId;
  displayName: string;
  description: string;
  maxMasterLeagues: number;
  maxLeagues: number;
  isPopular: boolean;
  unlimitedMasterLeagues: boolean;
  unlimitedCompetitions: boolean;
  isFree: boolean;
}

export const MASTER_LEAGUE_PLANS: Record<MasterLeaguePlanId, MasterLeaguePlanDef> = {
  basic: { id: 'basic', displayName: 'Basic', description: '1 master league, up to 3 competitions', maxMasterLeagues: 1, maxLeagues: 3, isPopular: false, unlimitedMasterLeagues: false, unlimitedCompetitions: false, isFree: true, },
  pro: { id: 'pro', displayName: 'Pro', description: '5 master leagues, up to 9 competitions each', maxMasterLeagues: 5, maxLeagues: 9, isPopular: true, unlimitedMasterLeagues: false, unlimitedCompetitions: false, isFree: false, },
  elite: { id: 'elite', displayName: 'Elite', description: 'Unlimited master leagues and competitions', maxMasterLeagues: 999, maxLeagues: 999, isPopular: false, unlimitedMasterLeagues: true, unlimitedCompetitions: true, isFree: false, },
};

export const PLAN_DURATIONS: Record<PlanDurationId, { id: PlanDurationId; displayName: string; months: number; discountLabel: string }> = {
  '3mo': { id: '3mo', displayName: '3 Months', months: 3, discountLabel: '' },
  '6mo': { id: '6mo', displayName: '6 Months', months: 6, discountLabel: 'Save 10%' },
  yearly: { id: 'yearly', displayName: '1 Year', months: 12, discountLabel: 'Save 25%' },
};

export function planOrder(id: MasterLeaguePlanId | null): number {
  if (id === 'basic') return 1;
  if (id === 'pro') return 2;
  if (id === 'elite') return 3;
  return 0;
}

export function planFromString(raw: unknown): MasterLeaguePlanId {
  const s = String(raw ?? '').trim().toLowerCase();
  if (s === 'pro' || s === 'elite' || s === 'basic') return s;
  return 'basic';
}

export interface OrganizerProfile {
  bannerUrl: string;
  logoUrl: string;
  bio: string;
  socialLinks: Record<string, string>;
  badge: string;
}

export interface MasterLeagueAnalytics {
  totalTournamentsCreated: number;
  totalParticipantsTeams: number;
  totalMatches: number;
}

export type VerificationStatus = 'none' | 'pending' | 'approved' | 'rejected';

export interface MasterLeague {
  id: string;
  name: string;
  ownerId: string;
  memberIds: string[];
  roles: Record<string, string>;
  updatedAtMs: number;
  plan: MasterLeaguePlanId;
  purchaseStatus: string;
  organizerProfile: OrganizerProfile;
  analytics: MasterLeagueAnalytics;
  followersCount: number;
  verificationStatus: VerificationStatus;
  verifiedBadge: boolean;
  verificationRequestType: 'initial' | 'renewal';
  verificationExpiresAtMs: number;
  verificationNote: string;
}

export function masterLeagueFromDoc(id: string, data: Record<string, any>): MasterLeague {
  return {
    id,
    name: (data.name ?? '').toString().trim(),
    ownerId: (data.ownerId ?? data.ownerUid ?? '').toString().trim(),
    memberIds: Array.isArray(data.memberIds) ? data.memberIds.map(String) : [],
    roles: typeof data.roles === 'object' && data.roles ? data.roles : {},
    updatedAtMs: Number(data.updatedAtMs) || 0,
    plan: planFromString(data.plan),
    purchaseStatus: (data.purchaseStatus ?? '').toString(),
    organizerProfile: {
      bannerUrl: (data.bannerUrl ?? '').toString(),
      logoUrl: (data.logoUrl ?? '').toString(),
      bio: (data.bio ?? '').toString(),
      socialLinks: typeof data.socialLinks === 'object' && data.socialLinks ? data.socialLinks : {},
      badge: (data.badge ?? '').toString(),
    },
    analytics: {
      totalTournamentsCreated: Number(data.totalTournamentsCreated) || 0,
      totalParticipantsTeams: Number(data.totalParticipantsTeams) || 0,
      totalMatches: Number(data.totalMatches) || 0,
    },
    followersCount: Number(data.followersCount) || 0,
    verificationStatus: (data.verificationStatus as VerificationStatus) ?? 'none',
    verifiedBadge: data.verifiedBadge === true,
    verificationRequestType: data.verificationRequestType === 'renewal' ? 'renewal' : 'initial',
    verificationExpiresAtMs: Number(data.verificationExpiresAtMs) || 0,
    verificationNote: (data.verificationNote ?? '').toString(),
  };
}

export function isOwner(ml: MasterLeague, uid: string): boolean {
  return !!uid && ml.ownerId === uid;
}

export function isVerifiedOrganizer(ml: MasterLeague): boolean {
  return ml.verifiedBadge || ml.verificationStatus === 'approved';
}

export function verificationExpired(ml: MasterLeague): boolean {
  if (ml.verificationExpiresAtMs <= 0) return false;
  return ml.verificationExpiresAtMs <= Date.now();
}
