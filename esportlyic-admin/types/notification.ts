// types/notification.ts

import type { AnnouncementSeverity } from './homeContent';

export type NotificationSegment = 'all' | 'pro' | 'elite' | 'league';

export interface SendNotificationRequest {
  segment: NotificationSegment;
  leagueId?: string;
  title: string;
  body: string;
  /**
   * Only meaningful when segment === 'all'. Creates a home_content
   * announcement (shown as a bottom sheet on home load) in addition to
   * the push, so a user with the app open still sees it.
   */
  postToHomeScreen: boolean;
  /** Only meaningful when postToHomeScreen is true. */
  homeScreenSeverity?: AnnouncementSeverity;
}

export interface SendNotificationResult {
  targetedUsers: number;
  tokensFound: number;
  successCount: number;
  failureCount: number;
  postedToHomeScreen: boolean;
}
