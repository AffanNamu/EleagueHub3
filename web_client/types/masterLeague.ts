export type MasterLeaguePlan = 'basic' | 'pro' | 'elite';

export interface OrganizerProfile {
  bio?: string;
  bannerUrl?: string;
  name: string;
  logoUrl: string;
  isVerified: boolean;
}

export interface MasterLeague {
  analytics?: any;
  id: string;
  ownerId: string;
  ownerUid: string; // Backward compatibility
  name: string;
  description: string;
  plan: MasterLeaguePlan;
  organizerProfile?: OrganizerProfile;
  followersCount: number;
  memberIds: string[];
  createdAtMs: number;
  // Entitlement properties
  isVerifiedOrganizer: boolean;
  verificationStatus: string;
}

export interface UserPlanSubscription {
  plan: MasterLeaguePlan;
  duration: string;
  purchasedAtMs: number;
  expiresAtMs: number;
  receiptId: string;
  provider: string;
}
