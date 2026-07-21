import { doc, getDoc, updateDoc } from 'firebase/firestore';
import { db, auth } from '@/lib/firebase';

// Mirrors MasterLeaguesRepositoryFirebase.updateOrganizerProfile — same
// field set, same 2000/2000/2000/80-char limits, same allowed social keys,
// writing directly onto the master_leagues/{id} document (there's no
// separate organizerProfile sub-doc in firestore.rules; bannerUrl/logoUrl/
// bio/badge/socialLinks live flat on the workspace doc).

const ALLOWED_SOCIAL_KEYS = [
  'website',
  'facebook',
  'instagram',
  'x',
  'twitter',
  'discord',
  'youtube',
  'twitch',
  'tiktok',
] as const;

export interface OrganizerProfileInput {
  bannerUrl: string;
  logoUrl: string;
  bio: string;
  badge: string;
  socialLinks: Record<string, string>;
}

function trim(value: string, max: number): string {
  const v = value.trim();
  return v.length <= max ? v : v.slice(0, max);
}

function sanitizeSocialLinks(input: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const key of ALLOWED_SOCIAL_KEYS) {
    const value = input[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      out[key] = trim(value, 2000);
    }
  }
  return out;
}

export async function updateOrganizerProfile(
  masterLeagueId: string,
  input: OrganizerProfileInput,
): Promise<void> {
  const uid = auth.currentUser?.uid.trim() ?? '';
  if (!uid) throw new Error('Please sign in and try again.');

  const id = masterLeagueId.trim();
  if (!id) throw new Error("We couldn't find that Master League.");

  const ref = doc(db, 'master_leagues', id);
  const snap = await getDoc(ref);
  if (!snap.exists()) throw new Error("We couldn't find that Master League.");

  const data = snap.data();
  const ownerId = (data.ownerId ?? data.ownerUid ?? '').toString().trim();
  if (ownerId !== uid) {
    throw new Error('Only the Master League owner can edit the organizer profile.');
  }

  const bannerUrl = trim(input.bannerUrl, 2000);
  const logoUrl = trim(input.logoUrl, 2000);
  const bio = trim(input.bio, 2000);
  const badge = trim(input.badge, 80);
  const socialLinks = sanitizeSocialLinks(input.socialLinks);

  await updateDoc(ref, {
    bannerUrl,
    logoUrl,
    bio,
    badge,
    socialLinks,
    updatedAtMs: Date.now(),
  });
}
