// types/linkAnalytics.ts
//
// Mirrors analytics_link_events/{eventId} and analytics_link_rollups/{id}
// exactly as defined in the rules you provided.

export type LinkEventType = 'share' | 'click';

export const LINK_ENTITY_TYPES = [
  'userProfile', 'competition', 'team', 'post', 'organizerWorkspace',
  'marketProduct', 'tournament', 'news', 'achievement',
] as const;
export type LinkEntityType = (typeof LINK_ENTITY_TYPES)[number];

export const LINK_CHANNELS = [
  'whatsapp', 'telegram', 'facebook', 'x', 'sms', 'copy_link',
  'system_share', 'deep_link', 'web_direct',
] as const;
export type LinkChannel = (typeof LINK_CHANNELS)[number];

export interface LinkRollup {
  rollupId: string;
  entityType: LinkEntityType;
  entityId: string;
  entityName: string | null;
  shareCount: number;
  clickCount: number;
  lastEventAtMs: number;
}

export interface ChannelBreakdownRow {
  channel: LinkChannel | string;
  shares: number;
  clicks: number;
}
