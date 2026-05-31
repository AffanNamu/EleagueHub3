// Web-only implementation using dart:js_util (works in both
// dart2js and dart2wasm / Flutter Web).
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

/// Returns true only when the current browser is a real mobile browser.
///
/// Rules:
///   width >= 900               → always desktop (return false)
///   UA contains 'cros'         → ChromeOS / Chromebook → desktop
///   UA contains 'windows nt'   → Windows desktop
///   UA contains 'macintosh'
///     without iphone/ipad      → macOS desktop
///   UA contains 'x11'/'linux'
///     without android          → Linux desktop
///   Otherwise check mobile tokens → mobile if found
bool isRealMobileBrowser(double width) {
  // Wide window → always desktop regardless of UA.
  if (width >= 900) return false;

  try {
    final navigator = js_util.getProperty<Object>(
      js_util.globalThis,
      'navigator',
    );
    final ua = js_util
        .getProperty<String>(navigator, 'userAgent')
        .toLowerCase();

    // ── Desktop OS tokens ─────────────────────────────────────────────
    if (ua.contains('cros')) return false;           // ChromeOS
    if (ua.contains('windows nt')) return false;     // Windows

    if (ua.contains('macintosh') || ua.contains('mac os x')) {
      if (!ua.contains('iphone') && !ua.contains('ipad')) {
        return false;                                // macOS
      }
    }

    if (ua.contains('x11') || ua.contains('linux')) {
      if (!ua.contains('android')) return false;    // Linux
    }

    // ── Known mobile tokens ───────────────────────────────────────────
    const mobileTokens = [
      'android',
      'iphone',
      'ipad',
      'ipod',
      'blackberry',
      'windows phone',
      'mobile',
      'opera mini',
      'opera mobi',
    ];

    return mobileTokens.any((t) => ua.contains(t));
  } catch (_) {
    // JS interop failed — fall back to width only.
    return width < 900;
  }
}
