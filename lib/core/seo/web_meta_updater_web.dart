// lib/core/seo/web_meta_updater_web.dart
//
// Web-only implementation. Only ever compiled in when targeting web (see
// the conditional import in web_meta_updater.dart) — dart:html does not
// exist on other platforms, so this file must never be imported directly
// by anything outside web_meta_updater.dart.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show document, MetaElement;

void platformSetTitle(String title) {
  html.document.title = title;
}

void platformSetMeta(String key, String content, {bool isProperty = false}) {
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
}
