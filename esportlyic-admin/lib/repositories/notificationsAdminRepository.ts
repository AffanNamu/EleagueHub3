// lib/repositories/notificationsAdminRepository.ts
//
// Two delivery paths, combined:
//
// 1. FCM push via users/{uid}/fcmTokens/{token} (confirmed against
//    push_messaging_service.dart). Reliable for background/killed-app
//    delivery. NOT reliable for foreground delivery on an admin
//    broadcast specifically — push_messaging_service.dart's onMessage
//    handler only acts on data.type 'league_chat' / 'private_message';
//    an admin broadcast doesn't match either, so a user with the app
//    open sees nothing from the push alone. That gap is why (2) exists.
//
// 2. home_content/{id} (type: 'announcement') — shown as a dismissible
//    bottom sheet on home load on both mobile and web. Writing here gives
//    a PERSISTENT notice any user sees on next app open/foreground,
//    closing the gap above. Only used for the 'all' segment — there's no
//    per-plan/per-league targeting field on this collection, so
//    pro/elite/league sends are push-only. This replaces the old
//    platform_announcements write: that collection/its historical docs
//    are left untouched (no destructive migration) but nothing new is
//    written there — home_content is the single source of truth for the
//    home-screen notice going forward.
//
// Same delegation precedent as global_chat_requests.review: this write
// goes through the Admin SDK (bypassing the isSuperAdmin()-only rule),
// so any admin holding 'notifications.send' can post here — not just
// the super admin. That's an intentional, visible expansion, same as
// elsewhere in this workspace.

import 'server-only';

import { getMessaging } from 'firebase-admin/messaging';
import { adminApp, adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import { createAnnouncementFromNotification } from '@/lib/repositories/homeContentAdminRepository';
import type { SendNotificationRequest, SendNotificationResult } from '@/types/notification';

export class NotificationSendError extends Error {}

async function getTargetUserIds(request: SendNotificationRequest): Promise<string[]> {
  if (request.segment === 'all') {
    const snap = await adminDb.collection('users').select().get();
    return snap.docs.map((d) => d.id);
  }

  if (request.segment === 'pro' || request.segment === 'elite') {
    const snap = await adminDb.collection('users').where('activePlanId', '==', request.segment).select().get();
    return snap.docs.map((d) => d.id);
  }

  if (request.segment === 'league') {
    const leagueId = request.leagueId?.trim();
    if (!leagueId) throw new NotificationSendError('leagueId is required for the "league" segment.');

    const leagueSnap = await adminDb.collection('leagues').doc(leagueId).get();
    if (!leagueSnap.exists) throw new NotificationSendError('League not found.');

    const memberIds = leagueSnap.data()?.memberIds;
    return Array.isArray(memberIds) ? memberIds : [];
  }

  throw new NotificationSendError('Invalid segment.');
}

async function getTokensForUsers(userIds: string[]): Promise<string[]> {
  const tokens: string[] = [];

  const BATCH_SIZE = 25;
  for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
    const batch = userIds.slice(i, i + BATCH_SIZE);
    const results = await Promise.all(
      batch.map((uid) => adminDb.collection('users').doc(uid).collection('fcmTokens').get()),
    );
    for (const snap of results) {
      for (const doc of snap.docs) {
        const token = doc.data()?.token;
        if (typeof token === 'string' && token.trim()) tokens.push(token.trim());
      }
    }
  }

  return Array.from(new Set(tokens));
}

export async function sendNotification(
  request: SendNotificationRequest,
  actor: { uid: string; email?: string | null },
): Promise<SendNotificationResult> {
  const title = request.title.trim();
  const body = request.body.trim();

  if (!title) throw new NotificationSendError('Title is required.');
  if (!body) throw new NotificationSendError('Body is required.');
  if (title.length > 120) throw new NotificationSendError('Title must be 120 characters or fewer.');
  if (body.length > 500) throw new NotificationSendError('Body must be 500 characters or fewer.');

  const userIds = await getTargetUserIds(request);
  const tokens = await getTokensForUsers(userIds);

  let successCount = 0;
  let failureCount = 0;

  if (tokens.length > 0) {
    const messaging = getMessaging(adminApp);
    const FCM_BATCH_SIZE = 500;
    for (let i = 0; i < tokens.length; i += FCM_BATCH_SIZE) {
      const batch = tokens.slice(i, i + FCM_BATCH_SIZE);
      const response = await messaging.sendEachForMulticast({
        tokens: batch,
        notification: { title, body },
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
    }
  }

  let postedToHomeScreen = false;
  if (request.segment === 'all' && request.postToHomeScreen) {
    await createAnnouncementFromNotification(
      { title, body, severity: request.homeScreenSeverity ?? 'info' },
      actor,
    );
    postedToHomeScreen = true;
  }

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'notification.send',
    targetType: 'notification_segment',
    targetId: request.segment === 'league' ? `league:${request.leagueId}` : request.segment,
    summary: `Sent notification "${title}" to segment "${request.segment}" — ${successCount} delivered, ${failureCount} failed, ${userIds.length} users targeted${postedToHomeScreen ? ', posted to home screen' : ''}`,
  });

  return { targetedUsers: userIds.length, tokensFound: tokens.length, successCount, failureCount, postedToHomeScreen };
}
