// lib/models/userProfile.ts
//
// Shared, isomorphic helpers for user plan/verification status —
// mirrors the getters on UserProfile (premiumActive, hasPlanActive,
// verifiedActive) so the admin UI's "is this plan actually active"
// logic matches the app's exactly, including expiry checks.

import type { AdminUserProfile } from '@/types/user';

export function planLabel(planId: string): string {
  switch (planId) {
    case 'basic':
      return 'Basic';
    case 'pro':
      return 'Pro';
    case 'elite':
      return 'Elite';
    default:
      return planId || 'None';
  }
}

export function isPlanCurrentlyActive(profile: AdminUserProfile, nowMs: number = Date.now()): boolean {
  const { plan } = profile;
  if (plan.activePlanId === 'basic') return true;
  if (plan.activePlanId === 'pro' || plan.activePlanId === 'elite') {
    return plan.planExpiresAtMs > nowMs;
  }
  // Backward-compatibility fallback for pre-plan-system premium users.
  return profile.isPremium && (profile.premiumExpiresAtMs <= 0 || profile.premiumExpiresAtMs > nowMs);
}

export function isBadgeCurrentlyActive(expiresAtMs: number | null, nowMs: number = Date.now()): boolean {
  if (expiresAtMs === null) return true; // manual_purchase / admin_granted never expire
  return expiresAtMs > nowMs;
}
