// lib/core/seo/web_meta_updater_stub.dart
//
// No-op stand-in for every non-web platform (Android, iOS, desktop). Same
// function signatures as web_meta_updater_web.dart — the conditional
// import in web_meta_updater.dart picks whichever one actually compiles
// for the current target, so callers never know which is in use.

void platformSetTitle(String title) {}

void platformSetMeta(String key, String content, {bool isProperty = false}) {}
