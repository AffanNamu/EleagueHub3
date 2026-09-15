import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import { updateOrganizer, deleteOrganizer, OrganizerAdminError } from '@/lib/repositories/organizersAdminRepository';
import type { OrganizerInput } from '@/types/organizer';

function parseInput(body: unknown): OrganizerInput {
  const b = (body ?? {}) as Record<string, unknown>;
  const social = (typeof b.socialLinks === 'object' && b.socialLinks !== null ? b.socialLinks : {}) as Record<
    string,
    unknown
  >;
  const pickSocial = (key: string) => (typeof social[key] === 'string' ? (social[key] as string) : '');

  return {
    name: typeof b.name === 'string' ? b.name : '',
    plan: b.plan === 'pro' || b.plan === 'elite' ? b.plan : 'basic',
    bio: typeof b.bio === 'string' ? b.bio : '',
    logoUrl: typeof b.logoUrl === 'string' ? b.logoUrl : '',
    bannerUrl: typeof b.bannerUrl === 'string' ? b.bannerUrl : '',
    country: typeof b.country === 'string' ? b.country : '',
    socialLinks: {
      website: pickSocial('website'),
      facebook: pickSocial('facebook'),
      instagram: pickSocial('instagram'),
      x: pickSocial('x'),
      twitter: pickSocial('twitter'),
      discord: pickSocial('discord'),
      youtube: pickSocial('youtube'),
      twitch: pickSocial('twitch'),
      tiktok: pickSocial('tiktok'),
    },
  };
}

export async function PATCH(request: Request, { params }: { params: { organizerId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'organizers.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const organizer = await updateOrganizer(params.organizerId, parseInput(body), {
      uid: identity!.uid,
      email: identity!.email,
    });
    return NextResponse.json({ organizer });
  } catch (err) {
    if (err instanceof OrganizerAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[update organizer]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}

export async function DELETE(_request: Request, { params }: { params: { organizerId: string } }) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'organizers.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    await deleteOrganizer(params.organizerId, { uid: identity!.uid, email: identity!.email });
    return NextResponse.json({ ok: true });
  } catch (err) {
    if (err instanceof OrganizerAdminError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[delete organizer]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
