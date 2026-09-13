import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { sendNotification, NotificationSendError } from '@/lib/repositories/notificationsAdminRepository';
import type { NotificationSegment } from '@/types/notification';
import type { AnnouncementSeverity } from '@/types/homeContent';

const VALID_SEGMENTS: NotificationSegment[] = ['all', 'pro', 'elite', 'league'];
const VALID_SEVERITIES: AnnouncementSeverity[] = ['info', 'warning', 'critical'];

export async function POST(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'notifications.send')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const segment = VALID_SEGMENTS.includes(body?.segment) ? body.segment : undefined;
    if (!segment) {
      return NextResponse.json({ error: 'Invalid segment.' }, { status: 400 });
    }

    const result = await sendNotification(
      {
        segment,
        leagueId: typeof body?.leagueId === 'string' ? body.leagueId : undefined,
        title: body?.title ?? '',
        body: body?.body ?? '',
        postToHomeScreen: body?.postToHomeScreen === true,
        homeScreenSeverity: VALID_SEVERITIES.includes(body?.homeScreenSeverity) ? body.homeScreenSeverity : undefined,
      },
      { uid: identity!.uid, email: identity!.email },
    );

    return NextResponse.json({ result });
  } catch (err) {
    if (err instanceof NotificationSendError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[send notification]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
