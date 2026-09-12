'use client';

import { BadgeCheck, Shield } from 'lucide-react';
import { ResolvedVerificationBadges } from '@/lib/profile/teamProfileRepository';

/**
 * Renders the same 4 distinct badges shown next to a name on mobile
 * (public_team_profile_screen.dart's name Row): legacy blue "verified"
 * tick, gold organizer, purple staff/ambassador, and the newer green
 * verified badge — in that same left-to-right order.
 */
export function VerificationBadgeIcons({ badges }: { badges: ResolvedVerificationBadges }) {
  return (
    <>
      {badges.verified && (
        <BadgeCheck className="w-5 h-5 text-[#1D9BF0]" aria-label="Verified account" />
      )}
      {badges.organizer && (
        <BadgeCheck className="w-5 h-5 text-amber-500" aria-label="Official Tournament Organizer" />
      )}
      {badges.staff && (
        <Shield className="w-5 h-5 text-[#7C3AED]" aria-label="Staff / Ambassador" />
      )}
      {badges.green && (
        <BadgeCheck className="w-5 h-5 text-[#22C55E]" aria-label="Verified User" />
      )}
    </>
  );
}
