// lib/repositories/homeContentAdminRepository.ts
//
// CRUD for the admin-controlled Home Content CMS (home_content collection).
// Same shape as every other admin repository in this workspace: Admin SDK
// writes (bypasses firestore.rules' isSuperAdmin()-only backstop — callers
// are already gated on home_content.manage by the API route), immutable
// audit log entry per mutation.
//
// ctaRoute is never trusted from the client as a raw string — it's always
// recomputed here from a curated destination type (see resolveCtaRoute),
// so a stored home_content doc can never point at an arbitrary/typo'd URL.

import 'server-only';

import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import { getLeague } from '@/lib/repositories/leaguesAdminRepository';
import { FIXED_ROUTES } from '@/types/homeContent';
import type { AnnouncementSeverity, HomeContentInput, HomeContentItem, HomeContentType } from '@/types/homeContent';

const COLLECTION = 'home_content';

export class HomeContentError extends Error {}

const VALID_TYPES: HomeContentType[] = ['hero', 'promo_card', 'announcement'];
const VALID_SEVERITIES: AnnouncementSeverity[] = ['info', 'warning', 'critical'];

function toHomeContentItem(id: string, data: FirebaseFirestore.DocumentData): HomeContentItem {
  return {
    id,
    type: VALID_TYPES.includes(data.type) ? data.type : 'promo_card',
    title: data.title ?? '',
    subtitle: data.subtitle ?? '',
    imageUrl: data.imageUrl ?? '',
    ctaLabel: data.ctaLabel ?? '',
    ctaRoute: data.ctaRoute ?? '',
    severity: VALID_SEVERITIES.includes(data.severity) ? data.severity : 'info',
    active: data.active === true,
    order: typeof data.order === 'number' ? data.order : 0,
    startAtMs: typeof data.startAtMs === 'number' ? data.startAtMs : null,
    endAtMs: typeof data.endAtMs === 'number' ? data.endAtMs : null,
    createdAtMs: typeof data.createdAtMs === 'number' ? data.createdAtMs : 0,
    updatedAtMs: typeof data.updatedAtMs === 'number' ? data.updatedAtMs : 0,
    createdBy: data.createdBy ?? '',
  };
}

/** Resolves a curated destination (never a raw client string) to a real, validated route. */
async function resolveCtaRoute(input: HomeContentInput): Promise<{ ctaRoute: string; ctaLabel: string }> {
  const ctaLabel = input.ctaLabel.trim();

  if (input.ctaDestinationType === 'none') {
    return { ctaRoute: '', ctaLabel: '' };
  }

  if (input.ctaDestinationType === 'league') {
    const leagueId = (input.ctaLeagueId ?? '').trim();
    if (!leagueId) throw new HomeContentError('A league must be selected for this destination.');
    const league = await getLeague(leagueId);
    if (!league) throw new HomeContentError(`League "${leagueId}" was not found.`);
    if (!ctaLabel) throw new HomeContentError('A CTA label is required.');
    return { ctaRoute: `/leagues/${leagueId}`, ctaLabel };
  }

  if (input.ctaDestinationType === 'fixed_route') {
    const route = (input.ctaFixedRoute ?? '').trim();
    const known = FIXED_ROUTES.some((r) => r.value === route);
    if (!known) throw new HomeContentError(`"${route}" is not a recognized destination.`);
    if (!ctaLabel) throw new HomeContentError('A CTA label is required.');
    return { ctaRoute: route, ctaLabel };
  }

  throw new HomeContentError('Invalid CTA destination type.');
}

function validateCommon(input: HomeContentInput): void {
  if (!VALID_TYPES.includes(input.type)) throw new HomeContentError('Invalid content type.');
  if (!input.title.trim()) throw new HomeContentError('Title is required.');
  if (input.title.length > 120) throw new HomeContentError('Title must be 120 characters or fewer.');
  if (input.subtitle.length > 400) throw new HomeContentError('Subtitle must be 400 characters or fewer.');
  if (!VALID_SEVERITIES.includes(input.severity)) throw new HomeContentError('Invalid severity.');
  if (input.startAtMs != null && input.endAtMs != null && input.startAtMs >= input.endAtMs) {
    throw new HomeContentError('Start date must be before end date.');
  }
}

export async function listHomeContent(): Promise<HomeContentItem[]> {
  const snap = await adminDb.collection(COLLECTION).orderBy('order', 'asc').get();
  return snap.docs.map((doc) => toHomeContentItem(doc.id, doc.data()));
}

export async function getHomeContent(id: string): Promise<HomeContentItem | null> {
  const snap = await adminDb.collection(COLLECTION).doc(id).get();
  if (!snap.exists) return null;
  return toHomeContentItem(snap.id, snap.data() ?? {});
}

export async function createHomeContent(
  input: HomeContentInput,
  actor: { uid: string; email?: string | null },
): Promise<HomeContentItem> {
  validateCommon(input);
  const { ctaRoute, ctaLabel } = await resolveCtaRoute(input);

  const now = Date.now();
  const ref = adminDb.collection(COLLECTION).doc();

  const data = {
    type: input.type,
    title: input.title.trim(),
    subtitle: input.subtitle.trim(),
    imageUrl: input.imageUrl.trim(),
    ctaLabel,
    ctaRoute,
    severity: input.severity,
    active: input.active,
    order: input.order,
    startAtMs: input.startAtMs,
    endAtMs: input.endAtMs,
    createdAtMs: now,
    updatedAtMs: now,
    createdBy: actor.uid,
  };

  await ref.set(data);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'home_content.create',
    targetType: 'home_content',
    targetId: ref.id,
    summary: `Created ${input.type} "${data.title}"`,
  });

  return { id: ref.id, ...data };
}

export async function updateHomeContent(
  id: string,
  input: HomeContentInput,
  actor: { uid: string; email?: string | null },
): Promise<HomeContentItem> {
  validateCommon(input);

  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) throw new HomeContentError('Content item not found.');

  const { ctaRoute, ctaLabel } = await resolveCtaRoute(input);
  const now = Date.now();

  const data = {
    type: input.type,
    title: input.title.trim(),
    subtitle: input.subtitle.trim(),
    imageUrl: input.imageUrl.trim(),
    ctaLabel,
    ctaRoute,
    severity: input.severity,
    active: input.active,
    order: input.order,
    startAtMs: input.startAtMs,
    endAtMs: input.endAtMs,
    updatedAtMs: now,
  };

  await ref.update(data);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'home_content.update',
    targetType: 'home_content',
    targetId: id,
    summary: `Updated ${input.type} "${data.title}"`,
  });

  return toHomeContentItem(id, { ...existing.data(), ...data });
}

export async function setHomeContentActive(
  id: string,
  active: boolean,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) throw new HomeContentError('Content item not found.');

  await ref.update({ active, updatedAtMs: Date.now() });

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: active ? 'home_content.publish' : 'home_content.unpublish',
    targetType: 'home_content',
    targetId: id,
    summary: `${active ? 'Published' : 'Unpublished'} "${existing.data()?.title ?? id}"`,
  });
}

export async function deleteHomeContent(id: string, actor: { uid: string; email?: string | null }): Promise<void> {
  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) throw new HomeContentError('Content item not found.');

  await ref.delete();

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'home_content.delete',
    targetType: 'home_content',
    targetId: id,
    summary: `Deleted "${existing.data()?.title ?? id}"`,
  });
}

/** Creates a home-screen announcement as a side effect of sending a platform notification. */
export async function createAnnouncementFromNotification(
  params: { title: string; body: string; severity: AnnouncementSeverity },
  actor: { uid: string; email?: string | null },
): Promise<string> {
  const now = Date.now();
  const ref = adminDb.collection(COLLECTION).doc();

  await ref.set({
    type: 'announcement',
    title: params.title.trim(),
    subtitle: params.body.trim(),
    imageUrl: '',
    ctaLabel: '',
    ctaRoute: '',
    severity: params.severity,
    active: true,
    order: 0,
    startAtMs: null,
    endAtMs: null,
    createdAtMs: now,
    updatedAtMs: now,
    createdBy: actor.uid,
  });

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'home_content.create',
    targetType: 'home_content',
    targetId: ref.id,
    summary: `Created announcement "${params.title.trim()}" via Send Notification`,
  });

  return ref.id;
}
