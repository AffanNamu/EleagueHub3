/// Cloudinary URL transformation utility.
///
/// All Cloudinary transform logic lives here and ONLY here.
/// Every widget that needs an optimized image calls this class.
/// No widget should ever contain raw Cloudinary URL manipulation.
///
/// Usage:
///   CloudinaryUtils.fill(url, width: 800, height: 280)
///   CloudinaryUtils.fit(url, width: 600)
///   CloudinaryUtils.thumb(url, size: 180)
library;

class CloudinaryUtils {
  CloudinaryUtils._();

  static const String _uploadMarker = '/image/upload/';

  // ── Public API ────────────────────────────────────────────────────────────

  /// Crop to exact dimensions, focus on the most important region.
  /// Use for banners, covers, hero images.
  static String fill(
    String rawUrl, {
    int? width,
    int? height,
  }) {
    return _transform(
      rawUrl,
      width:  width,
      height: height,
      crop:   'fill',
    );
  }

  /// Scale to fit within dimensions without cropping.
  /// Use for product images, logos where full content must be visible.
  static String fit(
    String rawUrl, {
    int? width,
    int? height,
  }) {
    return _transform(
      rawUrl,
      width:  width,
      height: height,
      crop:   'fit',
    );
  }

  /// Square thumbnail — equal width and height.
  /// Use for avatars, logos, profile pictures.
  static String thumb(
    String rawUrl, {
    required int size,
  }) {
    return _transform(
      rawUrl,
      width:  size,
      height: size,
      crop:   'thumb',
    );
  }

  // ── Private transform engine ──────────────────────────────────────────────

  static String _transform(
    String rawUrl, {
    int?   width,
    int?   height,
    String crop = 'fill',
  }) {
    final url = rawUrl.trim();
    if (url.isEmpty) return url;

    // Only transform genuine Cloudinary upload URLs.
    // Pass-through everything else untouched.
    if (!url.contains('res.cloudinary.com') ||
        !url.contains(_uploadMarker)) {
      return url;
    }

    final markerIdx = url.indexOf(_uploadMarker);
    if (markerIdx < 0) return url;

    final prefix = url.substring(
        0, markerIdx + _uploadMarker.length);
    final suffix = url.substring(
        markerIdx + _uploadMarker.length);

    // Build transform string
    final transforms = <String>[
      'f_auto',
      'q_auto',
      if (width  != null && width  > 0) 'w_$width',
      if (height != null && height > 0) 'h_$height',
      _cropParam(crop),
      // gravity only makes sense on fill/thumb
      if (crop == 'fill' || crop == 'thumb') 'g_auto',
    ].join(',');

    // If the suffix already has transforms injected, return as-is.
    // This prevents double-transforming a URL that already went
    // through this function.
    final firstSegment = suffix.split('/').first;
    if (firstSegment.contains('f_auto') ||
        firstSegment.contains('q_auto')) {
      return url;
    }

    return '$prefix$transforms/$suffix';
  }

  static String _cropParam(String crop) {
    switch (crop) {
      case 'fit':
        return 'c_fit';
      case 'thumb':
        return 'c_thumb';
      case 'fill':
      default:
        return 'c_fill';
    }
  }
}
