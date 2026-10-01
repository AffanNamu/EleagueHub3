// lib/highlights/highlightUpload.ts
//
// Mirrors lib/features/highlights/data/cloudinary_signed_video_upload_service.dart:
// signs via the Worker's POST /cloudinary/sign-highlight (never embeds the
// Cloudinary API secret client-side), then does a direct signed multipart
// upload to Cloudinary. Folder/public_id shape and signed-params set must
// stay byte-for-byte identical to what the Worker actually signs.
//
// NOTE (web-specific policy gap): unlike the Flutter app, this web client
// has no native video compression step (VideoCompressionService is a
// MethodChannel to Android/iOS native code with no browser equivalent).
// Instead of compressing, this enforces the same hard caps the Worker/
// firestore.rules already require client-side BEFORE upload, so a user
// finds out immediately rather than after a slow upload gets rejected by
// markUploadSucceeded's write.

import { auth } from '@/lib/firebase';

export const MAX_HIGHLIGHT_BYTES = 20 * 1024 * 1024; // keep in sync with VideoCompressionService.maxOutputBytes / firestore.rules maxBytes
export const MAX_HIGHLIGHT_DURATION_SECONDS = 90; // keep in sync with VideoCompressionService.maxDurationSeconds / firestore.rules maxSeconds

function signEndpoint(): string | null {
  const base = (process.env.NEXT_PUBLIC_WORKER_BASE_URL || '').trim();
  if (!base) return null;
  return `${base.replace(/\/$/, '')}/cloudinary/sign-highlight`;
}

async function requireIdToken(): Promise<string> {
  const user = auth.currentUser;
  if (!user) throw new Error('Please sign in and try again.');
  const token = await user.getIdToken();
  if (!token) throw new Error('Authentication token unavailable. Please try again.');
  return token;
}

/** Probes a local video File's duration (seconds) using a hidden <video> element. */
export function probeVideoDuration(file: File): Promise<number> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement('video');
    video.preload = 'metadata';
    video.onloadedmetadata = () => {
      const duration = video.duration;
      URL.revokeObjectURL(url);
      resolve(Number.isFinite(duration) ? duration : 0);
    };
    video.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Could not read video metadata.'));
    };
    video.src = url;
  });
}

/** Validates a picked file against the hard highlight policy caps before any upload starts. */
export async function validateHighlightFile(file: File): Promise<{ durationSeconds: number }> {
  if (!file.type.startsWith('video/')) {
    throw new Error('Please select a video file.');
  }
  if (file.size > MAX_HIGHLIGHT_BYTES) {
    throw new Error(`Video is too large (${(file.size / 1024 / 1024).toFixed(1)} MB). Maximum allowed is ${(MAX_HIGHLIGHT_BYTES / 1024 / 1024).toFixed(0)} MB.`);
  }

  const durationSeconds = await probeVideoDuration(file);
  if (durationSeconds <= 0) {
    throw new Error('Could not determine video duration.');
  }
  if (durationSeconds > MAX_HIGHLIGHT_DURATION_SECONDS) {
    throw new Error(`Video is too long (${durationSeconds.toFixed(0)}s). Maximum allowed is ${MAX_HIGHLIGHT_DURATION_SECONDS} seconds.`);
  }

  return { durationSeconds };
}

interface SignedParams {
  cloudName: string;
  apiKey: string;
  timestamp: number;
  signature: string;
}

async function signHighlightUpload(params: { folder: string; publicId: string }): Promise<SignedParams> {
  const endpoint = signEndpoint();
  if (!endpoint) throw new Error('Highlights upload is not configured (NEXT_PUBLIC_WORKER_BASE_URL missing).');

  const idToken = await requireIdToken();

  const res = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({
      params: {
        timestamp: Math.floor(Date.now() / 1000),
        folder: params.folder,
        public_id: params.publicId,
        overwrite: true,
      },
    }),
  });

  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(body?.error || `Sign request failed (${res.status}).`);
  }

  const signature = (body.signature || '').trim();
  const timestamp = Number(body.timestamp);
  if (!signature || !Number.isFinite(timestamp) || timestamp <= 0) {
    throw new Error('Invalid sign response: missing signature/timestamp.');
  }

  return {
    cloudName: (body.cloudName || '').trim(),
    apiKey: (body.apiKey || '').trim(),
    timestamp,
    signature,
  };
}

export interface HighlightUploadResult {
  publicId: string;
  secureUrl: string;
  format: string;
  bytes: number;
  duration: number;
}

/**
 * Uploads a highlight video to Cloudinary via signed upload.
 *
 * Cost controls: no eager transformations, no streaming_profile, no
 * unique_filename/use_filename (those aren't part of what the Worker
 * signs, so sending them would make Cloudinary reject the signature).
 */
export async function uploadHighlightVideo(params: {
  file: File;
  folder: string;
  publicId: string;
  onProgress?: (sentBytes: number, totalBytes: number) => void;
}): Promise<HighlightUploadResult> {
  const { file, folder, publicId, onProgress } = params;

  const signed = await signHighlightUpload({ folder, publicId });
  if (!signed.cloudName) throw new Error('Cloudinary cloud name missing from sign response.');

  const form = new FormData();
  form.append('file', file, `${publicId || 'highlight'}.mp4`);
  form.append('api_key', signed.apiKey);
  form.append('timestamp', String(signed.timestamp));
  form.append('signature', signed.signature);
  form.append('folder', folder);
  form.append('public_id', publicId);
  form.append('overwrite', 'true');

  const uploadUrl = `https://api.cloudinary.com/v1_1/${signed.cloudName}/video/upload`;

  return new Promise<HighlightUploadResult>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', uploadUrl);

    xhr.upload.onprogress = (e) => {
      if (onProgress && e.lengthComputable) onProgress(e.loaded, e.total);
    };

    xhr.onload = () => {
      let data: any = {};
      try {
        data = JSON.parse(xhr.responseText);
      } catch {
        // fall through to status check below
      }

      if (xhr.status < 200 || xhr.status >= 300) {
        const hint = data?.error?.message || `Upload failed (HTTP ${xhr.status}).`;
        reject(new Error(hint));
        return;
      }

      const secureUrl = (data.secure_url || '').trim();
      const publicIdOut = (data.public_id || '').trim();
      if (!secureUrl || !publicIdOut) {
        reject(new Error('Upload failed: missing secure_url/public_id.'));
        return;
      }

      resolve({
        publicId: publicIdOut,
        secureUrl,
        format: (data.format || '').trim(),
        bytes: typeof data.bytes === 'number' && data.bytes > 0 ? data.bytes : file.size,
        duration: typeof data.duration === 'number' ? data.duration : 0,
      });
    };

    xhr.onerror = () => reject(new Error('Upload failed. Please check your connection and try again.'));
    xhr.ontimeout = () => reject(new Error('Upload timed out. Please try again.'));
    xhr.timeout = 2 * 60 * 1000;

    xhr.send(form);
  });
}
