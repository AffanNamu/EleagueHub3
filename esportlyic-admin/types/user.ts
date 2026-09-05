// types/user.ts

export interface UserPlanSubscription {
  activePlanId: string;
  activePlanDurationId: string;
  planPurchasedAtMs: number;
  planExpiresAtMs: number;
  planReceiptId: string;
  planProvider: string;
}

export interface VerificationBadgesSummary {
  greenVerified: boolean;
  greenSource: string | null;
  greenExpiresAtMs: number | null;
  organizerVerified: boolean;
  organizerSource: string | null;
  organizerExpiresAtMs: number | null;
  staffVerified: boolean;
  staffSource: string | null;
  staffExpiresAtMs: number | null;
}

/** Mirrors the exact custom-claims shape set by the Cloudflare Worker's _setFirebaseCustomClaims. */
export interface OrganizerProClaims {
  organizerPro: boolean;
  organizerProPlan: string | null;
  organizerProDuration: string | null;
  organizerProExpiryMs: number | null;
}

export interface AdminUserProfile {
  userId: string;
  teamName: string;
  authProvider: string;
  createdAtMs: number;
  updatedAtMs: number;
  shareId: string;
  username: string;
  usernameLower: string;
  photoUrl: string;
  profileImageUrl: string;
  teamImageUrl: string;
  isPremium: boolean;
  premiumExpiresAtMs: number;
  isVerified: boolean;
  verificationStatus: string;
  plan: UserPlanSubscription;
  badges: VerificationBadgesSummary;
  followersCount: number;
  followingCount: number;
  chatMuted: boolean;
  chatBanned: boolean;
  isGlobalChatAdmin: boolean;
  claims: OrganizerProClaims;
}
