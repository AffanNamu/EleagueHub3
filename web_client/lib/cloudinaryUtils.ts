export class CloudinaryUtils {
  private static UPLOAD_MARKER = '/image/upload/';

  static fill(rawUrl: string, width?: number, height?: number): string {
    return this.transform(rawUrl, width, height, 'fill');
  }

  static fit(rawUrl: string, width?: number, height?: number): string {
    return this.transform(rawUrl, width, height, 'fit');
  }

  static thumb(rawUrl: string, size?: number): string {
    return this.transform(rawUrl, size, size, 'thumb');
  }

  private static transform(rawUrl: string, width?: number, height?: number, crop: string = 'fill'): string {
    const url = (rawUrl || '').trim();
    if (!url) return url;

    if (!url.includes('res.cloudinary.com') || !url.includes(this.UPLOAD_MARKER)) {
      return url;
    }

    const markerIdx = url.indexOf(this.UPLOAD_MARKER);
    if (markerIdx < 0) return url;

    const prefix = url.substring(0, markerIdx + this.UPLOAD_MARKER.length);
    const suffix = url.substring(markerIdx + this.UPLOAD_MARKER.length);

    // If already transformed, don't double-transform
    const firstSegment = suffix.split('/')[0];
    if (firstSegment.includes('f_auto') || firstSegment.includes('q_auto')) {
      return url;
    }

    const transforms: string[] = ['f_auto', 'q_auto'];
    if (width && width > 0) transforms.push(`w_${width}`);
    if (height && height > 0) transforms.push(`h_${height}`);
    
    transforms.push(`c_${crop}`);
    if (crop === 'fill' || crop === 'thumb') transforms.push('g_auto');

    return `${prefix}${transforms.join(',')}/${suffix}`;
  }
}
