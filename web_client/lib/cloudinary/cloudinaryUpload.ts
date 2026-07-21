// Mirrors lib/features/marketplace/data/cloudinaru_uploud_service.dart —
// same Cloudinary cloud name + UNSIGNED upload preset, so images uploaded
// from web and Flutter land in the same account/folders and are
// interchangeable.
//
// Cloudinary's unsigned upload endpoint is a plain multipart POST, no SDK
// needed on web: https://api.cloudinary.com/v1_1/{cloud}/image/upload

const CLOUD_NAME = (process.env.NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME || '').trim();
const UPLOAD_PRESET = (process.env.NEXT_PUBLIC_CLOUDINARY_PRESET || '').trim();

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB, same limit as OrganizerProfileScreen.dart

function assertConfigured(): void {
  if (!CLOUD_NAME || !UPLOAD_PRESET) {
    throw new Error(
      'Cloudinary is not configured. Missing NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME / NEXT_PUBLIC_CLOUDINARY_PRESET.',
    );
  }
}

export interface CloudinaryUploadResult {
  secureUrl: string;
}

/**
 * Uploads an image File to Cloudinary under the given folder using the
 * unsigned preset. Folder must start with 'eleaguehub/' to match the
 * existing namespace convention used by the Flutter app and any signed
 * worker routes that validate the folder prefix.
 */
export async function uploadImageFile(params: {
  file: File;
  folder: string;
  publicIdPrefix?: string;
}): Promise<CloudinaryUploadResult> {
  assertConfigured();

  const folder = params.folder.trim();
  if (!folder.startsWith('eleaguehub/')) {
    throw new Error('Invalid upload folder (must start with eleaguehub/).');
  }

  if (params.file.size > MAX_BYTES) {
    throw new Error('Image too large. Please select an image under 5 MB.');
  }
  if (!params.file.type.startsWith('image/')) {
    throw new Error('Please select an image file.');
  }

  const formData = new FormData();
  formData.append('file', params.file);
  formData.append('upload_preset', UPLOAD_PRESET);
  formData.append('folder', folder);
  if (params.publicIdPrefix) {
    formData.append('public_id', `${params.publicIdPrefix}_${Date.now()}`);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45000);

  try {
    const res = await fetch(`https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/upload`, {
      method: 'POST',
      body: formData,
      signal: controller.signal,
    });

    const parsed = await res.json().catch(() => ({}));

    if (!res.ok) {
      const msg = parsed?.error?.message?.trim();
      throw new Error(msg ? `Upload failed: ${msg}` : `Upload failed (HTTP ${res.status}).`);
    }

    const secureUrl = (parsed.secure_url || '').trim();
    if (!secureUrl) throw new Error('Upload failed: secure_url missing.');

    return { secureUrl };
  } catch (e: any) {
    if (e.name === 'AbortError') throw new Error('Upload timed out. Please try again.');
    throw e;
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Applies Cloudinary on-the-fly transforms (f_auto,q_auto + fill/fit crop)
 * to a secure_url, same logic as OrganizerProfileScreen.dart's
 * _cloudinaryOptimizedUrl — keeps banner/logo requests small.
 */
export function cloudinaryOptimizedUrl(
  url: string,
  opts: { width?: number; height?: number; crop?: 'fill' | 'fit' } = {},
): string {
  const u = url.trim();
  if (!u) return u;
  const marker = '/image/upload/';
  const idx = u.indexOf(marker);
  if (!u.includes('res.cloudinary.com') || idx < 0) return u;

  const prefix = u.slice(0, idx + marker.length);
  const suffix = u.slice(idx + marker.length);

  const crop = opts.crop ?? 'fill';
  const transforms = [
    'f_auto',
    'q_auto',
    opts.width ? `w_${opts.width}` : null,
    opts.height ? `h_${opts.height}` : null,
    crop === 'fit' ? 'c_fit' : 'c_fill',
    crop !== 'fit' ? 'g_auto' : null,
  ]
    .filter(Boolean)
    .join(',');

  const parts = suffix.split('/');
  const first = parts[0] ?? '';
  const isVersionOnly = /^v\d+$/.test(first);

  if (!isVersionOnly) {
    if (first.includes('f_auto') || first.includes('q_auto')) return u;
    parts[0] = `f_auto,q_auto,${first}`;
    return prefix + parts.join('/');
  }

  return `${prefix}${transforms}/${suffix}`;
}
