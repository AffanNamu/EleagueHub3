// types/homeContent.ts
//
// Admin-controlled Home Content CMS. One collection (home_content) backs
// three presentation types the mobile/web home screens consume:
//   - hero: the top hero/promotional slot
//   - promo_card: a smaller card in a promo strip
//   - announcement: shown as a dismissible bottom sheet on home load
//     (replaces the old platform_announcements "post to home screen" banner)
//
// ctaDestination is a curated allowlist, not a free-text URL — either a
// real league (validated to exist server-side) or one of a fixed set of
// known in-app routes. This avoids typo'd/dead links and any open-redirect
// surface a free-text field would introduce.
//
// FIXED_ROUTES is intentionally short: every entry was checked against
// BOTH lib/core/routing/app_router.dart (mobile) and web_client/app's
// route tree, not just one. '/premium' and '/master-leagues/discovery'
// exist on web but have no registered route on mobile at all, so they're
// deliberately left out — a mobile user tapping either would hit a dead
// link. Add a route to both platforms before adding it here.

export type HomeContentType = 'hero' | 'promo_card' | 'announcement';

export type AnnouncementSeverity = 'info' | 'warning' | 'critical';

export type CtaDestinationType = 'none' | 'league' | 'fixed_route';

export const FIXED_ROUTES: { value: string; label: string }[] = [
  { value: '/organizer-feed', label: 'Organizer Feed' },
  { value: '/global-chat', label: 'Global Chat' },
  { value: '/marketplace', label: 'Marketplace' },
  { value: '/discovery/community', label: 'Community Discovery' },
];

export interface HomeContentItem {
  id: string;
  type: HomeContentType;
  title: string;
  subtitle: string;
  imageUrl: string;
  ctaLabel: string;
  /** Resolved, validated destination path — computed server-side, never trusted raw from the client. */
  ctaRoute: string;
  /** Only meaningful for type === 'announcement'. */
  severity: AnnouncementSeverity;
  active: boolean;
  order: number;
  startAtMs: number | null;
  endAtMs: number | null;
  createdAtMs: number;
  updatedAtMs: number;
  createdBy: string;
}

export interface HomeContentInput {
  type: HomeContentType;
  title: string;
  subtitle: string;
  imageUrl: string;
  ctaLabel: string;
  ctaDestinationType: CtaDestinationType;
  /** Required when ctaDestinationType === 'league'. */
  ctaLeagueId?: string;
  /** Required when ctaDestinationType === 'fixed_route'. Must be one of FIXED_ROUTES. */
  ctaFixedRoute?: string;
  severity: AnnouncementSeverity;
  active: boolean;
  order: number;
  startAtMs: number | null;
  endAtMs: number | null;
}
