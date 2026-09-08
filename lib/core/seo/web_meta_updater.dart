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
import 'package:flutter/foundation.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show document, MetaElement;

class WebMetaUpdater {
  WebMetaUpdater._();

  /// Sets the browser tab title. No-op on non-web platforms.
  static void setTitle(String title) {
    if (!kIsWeb) return;
    try {
      html.document.title = title;
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
      final selector = isProperty ? 'meta[property="$key"]' : 'meta[name="$key"]';
      final existing = html.document.querySelector(selector);
      if (existing is html.MetaElement) {
        existing.content = content;
        return;
      }
      final meta = html.MetaElement();
      if (isProperty) {
        meta.setAttribute('property', key);
      } else {
        meta.name = key;
      }
      meta.content = content;
      html.document.head?.append(meta);
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
