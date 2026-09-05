// types/organizer.ts
//
// Full organizer workspace (master_leagues/{id}) type for the admin
// Organizers module — a superset of MasterLeagueSummary used in
// Verification review, adding membership/branding/analytics fields
// confirmed in master_league.dart.

export type MasterLeaguePlanId = 'basic' | 'pro' | 'elite';

export interface OrganizerSocialLinks {
  website?: string;
  facebook?: string;
  instagram?: string;
  x?: string;
  twitter?: string;
  discord?: string;
  youtube?: string;
  twitch?: string;
  tiktok?: string;
}

export interface Organizer {
  id: string;
  name: string;
  ownerId: string;
  memberIds: string[];
  roles: Record<string, string>;
  plan: MasterLeaguePlanId;
  purchaseStatus: string;
  bannerUrl: string;
  logoUrl: string;
  bio: string;
  badge: string;
  socialLinks: OrganizerSocialLinks;
  country: string;
  usernameLower: string;
  verificationStatus: 'none' | 'pending' | 'approved' | 'rejected' | 'info_requested';
  verifiedBadge: boolean;
  verificationExpiresAtMs: number;
  totalTournamentsCreated: number;
  totalParticipantsTeams: number;
  totalMatches: number;
  followersCount: number;
  createdAtMs: number;
  updatedAtMs: number;
}
