// lib/highlights/types.ts
//
// Mirrors lib/features/highlights/domain/match_highlight.dart field-for-field.
//
// Firestore structure (REQUIRED, independent of leagues/{id}/matches):
// matches/{matchId}/highlights/{highlightId}

import { DocumentSnapshot, Timestamp } from 'firebase/firestore';

export const HIGHLIGHT_STATUS_UPLOADING = 'UPLOADING';
export const HIGHLIGHT_STATUS_PROCESSING = 'PROCESSING';
export const HIGHLIGHT_STATUS_APPROVED = 'APPROVED';

export interface MatchHighlight {
  id: string;

  matchId: string;
  leagueId: string;
  teamId: string;

  uploadedBy: string;

  /** match_highlights/{leagueId}/{matchId}/{teamId}/{highlightId} */
  cloudinaryPublicId: string;

  secureUrl: string;
  thumbnailUrl: string;

  duration: number;
  size: number;
  format: string;

  status: string;

  createdAt: Timestamp | null;
  updatedAt: Timestamp | null;
}

export function isHighlightUploading(h: MatchHighlight): boolean {
  return h.status === HIGHLIGHT_STATUS_UPLOADING;
}
export function isHighlightProcessing(h: MatchHighlight): boolean {
  return h.status === HIGHLIGHT_STATUS_PROCESSING;
}
export function isHighlightApproved(h: MatchHighlight): boolean {
  return h.status === HIGHLIGHT_STATUS_APPROVED;
}

function stringFrom(v: unknown): string {
  if (typeof v === 'string') return v.trim();
  return v == null ? '' : String(v).trim();
}

function numberFrom(v: unknown, fallback = 0): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = Number(v.trim());
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}

export function parseMatchHighlight(doc: DocumentSnapshot): MatchHighlight {
  const data = doc.data() || {};
  const status = stringFrom(data.status);

  return {
    id: doc.id,
    matchId: stringFrom(data.matchId),
    leagueId: stringFrom(data.leagueId),
    teamId: stringFrom(data.teamId),
    uploadedBy: stringFrom(data.uploadedBy),
    cloudinaryPublicId: stringFrom(data.cloudinaryPublicId),
    secureUrl: stringFrom(data.secureUrl),
    thumbnailUrl: stringFrom(data.thumbnailUrl),
    duration: numberFrom(data.duration, 0),
    size: numberFrom(data.size, 0),
    format: stringFrom(data.format),
    status: status.length ? status : HIGHLIGHT_STATUS_UPLOADING,
    createdAt: data.createdAt instanceof Timestamp ? data.createdAt : null,
    updatedAt: data.updatedAt instanceof Timestamp ? data.updatedAt : null,
  };
}

/**
 * Lightweight thumbnail URL via Cloudinary on-the-fly video transforms --
 * mirrors CloudinarySignedVideoUploadService.buildLightweightThumbnailUrl.
 */
export function buildLightweightThumbnailUrl(secureVideoUrl: string, width = 480, second = 0): string {
  const u = secureVideoUrl.trim();
  if (!u) return '';

  const marker = '/video/upload/';
  const idx = u.indexOf(marker);
  if (idx < 0) return '';

  const prefix = u.slice(0, idx + marker.length);
  const suffix = u.slice(idx + marker.length);

  const so = second < 0 ? 0 : second;
  const transforms = `so_${so},f_jpg,q_auto,w_${width}`;

  const fixedSuffix = suffix.includes('.') ? suffix.replace(/\.[A-Za-z0-9]+$/, '.jpg') : `${suffix}.jpg`;

  return `${prefix}${transforms}/${fixedSuffix}`;
}
