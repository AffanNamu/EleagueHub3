'use client';

import { useEffect } from 'react';
import { useParams } from 'next/navigation';
import { recordLinkClick } from '@/lib/services/linkAnalyticsService';
import { ProfileDetailView } from '@/components/profile/ProfileDetailView';

/**
 * The public `/team/{id}` share link. Mirrors RouteResolver's 'team' case
 * (lib/core/routing/route_resolver.dart): there is no separate Team
 * aggregate in this app — a team IS the owning user's profile — so this
 * renders the exact same ProfileDetailView as /profile/[id] and /u/[username],
 * keyed by the same uid, just reached via the "team" public URL segment.
 */
export default function TeamProfilePage() {
  const params = useParams();
  const teamId = ((params.id as string) || '').trim();

  useEffect(() => {
    if (teamId) recordLinkClick('team', teamId);
  }, [teamId]);

  return <ProfileDetailView routeUid={teamId} />;
}
