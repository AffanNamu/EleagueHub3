import 'dart:async';

// ---------------------------------------------------------------------------
// Conditional import:
// - On Web (dart:html available)  → stub (no google_mobile_ads)
// - On Mobile (dart:io available) → real mobile implementation
//
// The key trick: we use `dart.library.io` for mobile and
// `dart.library.html` for web. dart2js only compiles the stub.
// ---------------------------------------------------------------------------
import 'rewarded_ad_manager_stub.dart'
    if (dart.library.io) 'rewarded_ad_manager_mobile.dart' as _impl;

/// Singleton facade — same API on every platform.
///
/// Free users  → must earn reward before action proceeds.
/// Paid users  → caller skips this entirely (no ad shown).
/// Web/desktop → stub always returns true (ads not supported).
class RewardedAdManager {
  RewardedAdManager._();
  static final RewardedAdManager instance = RewardedAdManager._();

  /// Preload a rewarded ad in the background.
  /// Safe to call on any platform — no-ops on web/desktop.
  Future<void> preload({String placement = 'preload'}) =>
      _impl.preload(placement: placement);

  /// Gate: show the rewarded ad and return whether reward was earned.
  ///
  /// Returns `true`  → reward earned → caller may proceed.
  /// Returns `false` → ad skipped / failed → caller must NOT proceed.
  ///
  /// On Web / unsupported platforms returns `true` immediately.
  Future<bool> showRewardedGate({required String placement}) =>
      _impl.showRewardedGate(placement: placement);
}
