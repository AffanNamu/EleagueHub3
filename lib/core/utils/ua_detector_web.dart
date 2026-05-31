// Web-only implementation (safe because it is imported ONLY on web via
// conditional import in ua_detector.dart).
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

/// Detect a "real mobile browser" using BOTH width + user-agent.
///
/// Goals:
/// - Chromebook should be treated as DESKTOP even if narrow.
/// - Desktop-mode on phone (request desktop site) should behave like desktop
///   when width becomes large.
/// - Small phones should be treated as mobile.
///
/// Rules:
/// - width >= 900  -> desktop
/// - UA contains 'cros' (ChromeOS) -> desktop
/// - else if UA contains common mobile tokens -> mobile
/// - else fallback to width < 900
bool isRealMobileBrowser(double width) {
  if (width >= 900) return false;

  try {
    final navigator = js_util.getProperty<Object>(js_util.globalThis, 'navigator');
    final ua = js_util.getProperty<String>(navigator, 'userAgent').toLowerCase();

    // ChromeOS / Chromebook -> always desktop
    if (ua.contains('cros')) return false;

    // Common mobile tokens
    const mobileTokens = <String>[
      'android',
      'iphone',
      'ipad',
      'ipod',
      'mobile',
      'windows phone',
      'blackberry',
      'opera mini',
      'opera mobi',
    ];

    if (mobileTokens.any(ua.contains)) return true;

    // Fallback: width only
    return width < 900;
  } catch (_) {
    // If JS access fails, fallback to width only.
    return width < 900;
  }
}
