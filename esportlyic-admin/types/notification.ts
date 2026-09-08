// types/notification.ts

export type NotificationSegment = 'all' | 'pro' | 'elite' | 'league';

export interface SendNotificationRequest {
  segment: NotificationSegment;
  leagueId?: string;
  title: string;
  body: string;
  /** Only meaningful when segment === 'all'. Writes a persistent home-screen banner (platform_announcements) in addition to the push. */
  postToHomeScreen: boolean;
}

export interface SendNotificationResult {
  targetedUsers: number;
  tokensFound: number;
  successCount: number;
  failureCount: number;
  postedToHomeScreen: boolean;
}
