// lib/core/config/ad_config.dart
//
// Single source of truth for platform-specific AdMob ad unit IDs. No ad
// widget should hardcode an ad unit ID directly -- route it through here
// instead, so Android and iOS configuration can never accidentally get
// swapped or mixed, and so a future real iOS ad unit is a one-line change
// in exactly one place.
//
// Android already has a real, live production AdMob account
// (ca-app-pub-9284565371998347, App ID ca-app-pub-9284565371998347~4995728889
// -- see android/app/src/main/AndroidManifest.xml) with real ad units for
// both rewarded (rewarded_ad_manager_mobile.dart) and banner placements.
// Android must NEVER be pointed at a Google test ad unit ID.
//
// iOS does not have a production banner ad unit yet, so it uses Google's
// official public TEST banner ID (ca-app-pub-3940256099942544/...) until
// one is created in the same AdMob account. That is a deliberate,
// temporary exception -- NOT a template to follow for Android.

import 'package:flutter/foundation.dart';

class AdConfig {
  const AdConfig._();

  // ── Banner ─────────────────────────────────────────────────────────────

  /// Real production Android banner ad unit (ca-app-pub-9284565371998347
  /// account, created 2026-09 alongside the existing rewarded ad units).
  static const String _bannerAndroid =
      'ca-app-pub-9284565371998347/2610225118';

  /// Google's official public TEST banner ad unit for iOS --
  /// https://developers.google.com/admob/ios/test-ads. Placeholder only:
  /// replace with a real ca-app-pub-9284565371998347 banner ad unit for
  /// iOS once one exists, and remove this comment.
  static const String _bannerIOSTest =
      'ca-app-pub-3940256099942544/2934735716';

  static String get bannerAdUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? _bannerIOSTest
      : _bannerAndroid;
}
