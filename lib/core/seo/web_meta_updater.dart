// lib/core/seo/web_meta_updater.dart
//
// WebMetaUpdater — updates the browser tab's <title> (and, where present,
// the OG/Twitter meta tags already in web/index.html) client-side when
// the user navigates to a shareable entity screen.
//
// IMPORTANT SCOPE NOTE: this does NOT solve social-media crawler previews
// on its own — crawlers generally do not execute JavaScript, which is why
// deploy/cloudflare-worker/seo-meta-injector.js exists for that purpose.
// This class instead improves:
//   - the browser tab title or PWA task-switcher title while the app is
//     open (e.g. "Mohammed | eSportlyic" instead of a generic app name);
//   - in-app browsers that DO run JS before generating a preview (some
//     Instagram/TikTok in-app browsers behave this way for the first few
//     seconds after load, unlike the sandboxed HEAD-only fetch used by
//     Facebook/Twitter/Telegram's own preview services).
//
// Safe to call on non-web platforms — every method is a no-op there.
//
// FIXED: this file used to import 'dart:html' directly and unconditionally.
// dart:html does not exist outside web builds, so ANY screen reachable from
// this file (via app_router.dart) broke the Android/iOS release build
// entirely, even though every call here was already guarded by kIsWeb at
// runtime — the guard doesn't help at COMPILE time. Moved the actual
// dart:html-touching code to web_meta_updater_web.dart, with
// web_meta_updater_stub.dart as the no-op compiled in everywhere else,
// selected via conditional import below — same pattern this project
// already uses for country_resolver_factory.dart and
// admob_initializer.dart. The public API (WebMetaUpdater.setTitle, etc.)
// is unchanged, so no caller needs to change.
import 'package:flutter/foundation.dart';

import 'web_meta_updater_stub.dart'
    if (dart.library.html) 'web_meta_updater_web.dart';

class WebMetaUpdater {
  WebMetaUpdater._();

  /// Sets the browser tab title. No-op on non-web platforms.
  static void setTitle(String title) {
    if (!kIsWeb) return;
    try {
      platformSetTitle(title);
    } catch (_) {
      // Never let a meta-tag update crash navigation.
    }
  }

  /// Updates (or inserts) a `<meta name="..." content="...">` or
  /// `<meta property="..." content="...">` tag. [isProperty] selects
  /// between the `name` attribute (used by `description`, Twitter tags)
  /// and the `property` attribute (used by Open Graph `og:*` tags).
  static void setMeta(String key, String content, {bool isProperty = false}) {
    if (!kIsWeb) return;
    try {
      platformSetMeta(key, content, isProperty: isProperty);
    } catch (_) {
      // Never let a meta-tag update crash navigation.
    }
  }

  /// Convenience: updates title + description + the standard OG/Twitter
  /// trio in one call, matching the shape produced by the Cloudflare
  /// Worker meta injector for crawler requests (see
  /// deploy/cloudflare-worker/seo-meta-injector.js) so client-rendered
  /// and crawler-rendered previews stay visually consistent.
  static void applyEntityMeta({
    required String title,
    required String description,
    String imageUrl = '',
  }) {
    setTitle(title);
    setMeta('description', description);
    setMeta('og:title', title, isProperty: true);
    setMeta('og:description', description, isProperty: true);
    setMeta('twitter:title', title);
    setMeta('twitter:description', description);
    if (imageUrl.trim().isNotEmpty) {
      setMeta('og:image', imageUrl, isProperty: true);
      setMeta('twitter:image', imageUrl);
    }
  }

  /// Resets meta tags back to the app-wide defaults — call this from a
  /// screen's dispose() if it set entity-specific meta, so navigating
  /// away (e.g. back to the home feed) doesn't leave a stale tab title.
  static void resetToDefault({
    String title = 'eSportlyic',
    String description =
        'Join leagues, follow organizers, and build your competitive eFootball team.',
  }) {
    applyEntityMeta(title: title, description: description);
  }
}
