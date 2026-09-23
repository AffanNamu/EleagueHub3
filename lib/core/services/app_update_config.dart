// lib/core/services/app_update_config.dart
//
// Mirrors app_config/app_update -- the Firestore doc the esportlyic-admin
// dashboard's Settings > App Updates page writes to, and the one thing
// AuthRouterRefresh's update listener (app_router.dart) reads to decide
// whether the currently-installed build is behind and, if so, whether
// that's a skippable nudge or a hard block.
//
// Mobile-app-only feature: never read on web (kIsWeb-guarded at every
// call site), matching how this app is the only surface this update
// mechanism applies to.

import 'dart:io';

class AppUpdateConfig {
  const AppUpdateConfig({
    required this.latestBuildNumber,
    required this.latestVersionName,
    required this.forceUpdate,
    required this.releaseNotes,
    required this.playStoreUrl,
    required this.appStoreUrl,
  });

  final int latestBuildNumber;
  final String latestVersionName;
  final bool forceUpdate;
  final String releaseNotes;
  final String playStoreUrl;
  final String appStoreUrl;

  factory AppUpdateConfig.fromMap(Map<String, dynamic> map) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v'.trim()) ?? 0;
    }

    String asString(dynamic v) => (v as String?)?.trim() ?? '';

    return AppUpdateConfig(
      latestBuildNumber: asInt(map['latestBuildNumber']),
      latestVersionName: asString(map['latestVersionName']),
      forceUpdate: map['forceUpdate'] == true,
      releaseNotes: asString(map['releaseNotes']),
      playStoreUrl: asString(map['playStoreUrl']),
      appStoreUrl: asString(map['appStoreUrl']),
    );
  }

  /// The store URL for the platform this code is currently running on.
  String get storeUrlForThisPlatform {
    if (Platform.isIOS) return appStoreUrl;
    return playStoreUrl;
  }
}
