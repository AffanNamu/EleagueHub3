// lib/cloudinary/adminCloudinaryUpload.ts
//
// Client-side unsigned upload, mirroring web_client's
// lib/cloudinary/cloudinaryUpload.ts exactly — same Cloudinary account,
// same unsigned preset, same 'eleaguehub/' folder namespace, so images
// uploaded here are interchangeable with the rest of the platform. This
// is the first thing in esportlyic-admin that uploads media at all, but
// it deliberately reuses the existing account/preset rather than
// introducing a second storage provider.
//
// Requires NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME / NEXT_PUBLIC_CLOUDINARY_PRESET
// to be set in this app's own environment (same values as web_client's).

const CLOUD_NAME = (process.env.NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME || '').trim();
const UPLOAD_PRESET = (process.env.NEXT_PUBLIC_CLOUDINARY_PRESET || '').trim();

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB, same limit as the rest of the platform

function assertConfigured(): void {
  if (!CLOUD_NAME || !UPLOAD_PRESET) {
    throw new Error(
      'Cloudinary is not configured. Missing NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME / NEXT_PUBLIC_CLOUDINARY_PRESET.',
    );
  }
}

export async function uploadHomeContentImage(file: File): Promise<string> {
  assertConfigured();

  if (file.size > MAX_BYTES) {
    throw new Error('Image too large. Please select an image under 5 MB.');
  }
  if (!file.type.startsWith('image/')) {
    throw new Error('Please select an image file.');
  }

  const formData = new FormData();
  formData.append('file', file);
  formData.append('upload_preset', UPLOAD_PRESET);
  formData.append('folder', 'eleaguehub/home_content');

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

    return secureUrl;
  } catch (e) {
    if (e instanceof Error && e.name === 'AbortError') throw new Error('Upload timed out. Please try again.');
    throw e;
  } finally {
    clearTimeout(timeout);
  }
}
