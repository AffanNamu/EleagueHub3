//lib/core/utils/cloudinary_media_utils.dart
//
// Pure, dependency-free helpers for working with Cloudinary delivery URLs.
// Nothing here touches the network — it only does string manipulation —
// so it works for any Cloudinary URL regardless of cloud name or resource
// type (image vs video/audio), and needs no new package dependency.
library;

class CloudinaryMediaUtils {
  CloudinaryMediaUtils._();

  /// Inserts a Cloudinary transformation segment right after `/upload/` in
  /// a standard delivery URL, e.g.:
  ///   https://res.cloudinary.com/demo/image/upload/v123/folder/file.jpg
  /// becomes:
  ///   https://res.cloudinary.com/demo/image/upload/q_auto,f_auto,w_640,c_limit/v123/folder/file.jpg
  ///
  /// If the URL doesn't look like a Cloudinary delivery URL (no `/upload/`
  /// segment), the original URL is returned unchanged so callers can always
  /// pass this through safely without special-casing malformed input.
  static String withTransformation(String url, String transformation) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return trimmedUrl;

    const marker = '/upload/';
    final idx = trimmedUrl.indexOf(marker);
    if (idx == -1) return trimmedUrl;

    final insertAt = idx + marker.length;
    final rest = trimmedUrl.substring(insertAt);

    // Defensive: don't double up if this is ever called twice on the
    // same URL (e.g. a re-render passing an already-transformed value).
    if (rest.startsWith('$transformation/')) return trimmedUrl;

    return '${trimmedUrl.substring(0, insertAt)}$transformation/$rest';
  }

  /// Lightweight, low-bandwidth thumbnail for inline chat previews.
  /// - q_auto: automatic quality
  /// - f_auto: automatic format (webp/avif where the client supports it)
  /// - w_$maxWidth,c_limit: never upscale, cap width for bubble-sized previews
  static String imageThumbnail(String url, {int maxWidth = 640}) {
    return withTransformation(url, 'q_auto,f_auto,w_$maxWidth,c_limit');
  }

  /// Full-quality delivery URL used only when the user explicitly taps
  /// Download. Still applies q_auto/f_auto (a safe, effectively-lossless
  /// choice) but does not resize, so the downloaded file is full resolution.
  static String imageFullQuality(String url) {
    return withTransformation(url, 'q_auto,f_auto');
  }

  /// Deterministic, filesystem-safe cache key for a given URL. Cloudinary
  /// URLs are unique per asset (public_id + version) already; folding in a
  /// short non-cryptographic hash of the whole URL is just a safety net
  /// against unexpected characters or unusually long paths.
  static String cacheKeyFor(String url) {
    final trimmed = url.trim();
    final hash = _fnv1a(trimmed);

    final segments =
        trimmed.split('/').where((s) => s.isNotEmpty).toList(growable: false);
    final tail = segments.length <= 2
        ? segments.join('_')
        : segments.sublist(segments.length - 2).join('_');

    final safeTail = tail.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '${hash}_$safeTail';
  }

  /// Best-effort file extension guess from the URL path, defaulting to
  /// [fallback] when none can be determined (Cloudinary URLs almost always
  /// carry one, but this keeps callers safe regardless).
  static String extensionFor(String url, {required String fallback}) {
    final trimmed = url.trim();
    final withoutQuery = trimmed.split('?').first;
    final lastSegment = withoutQuery.split('/').last;
    final dot = lastSegment.lastIndexOf('.');
    if (dot == -1 || dot == lastSegment.length - 1) return fallback;

    final ext = lastSegment.substring(dot + 1).toLowerCase();
    if (ext.isEmpty || ext.length > 5) return fallback;
    return ext;
  }

  /// Simple, dependency-free 32-bit FNV-1a hash rendered as hex. Not
  /// cryptographic — only used to build stable, collision-resistant-enough
  /// local cache filenames without adding a `crypto` dependency.
  static String _fnv1a(String input) {
    const int prime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
