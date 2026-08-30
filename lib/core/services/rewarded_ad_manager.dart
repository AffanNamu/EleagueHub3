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

  /// True if a rewarded ad is already loaded and ready to be shown
  /// instantly, with no load delay. Always `true` on web/desktop, since
  /// no ad is ever shown there.
  bool get isReady => _impl.isReady;

  /// Preload a rewarded ad in the background.
  /// Safe to call on any platform — no-ops on web/desktop.
  Future<void> preload({String placement = 'preload'}) =>
      _impl.preload(placement: placement);

  /// Waits, bounded by [timeout], for a background preload to finish —
  /// without showing anything. Returns `true` once an ad is ready (or
  /// immediately on web/desktop). Returns `false` if it doesn't become
  /// ready within [timeout]; the load keeps running in the background
  /// regardless, so callers can fall back to their existing "ad missing"
  /// behavior without losing the in-flight preload.
  Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 4),
  }) =>
      _impl.waitUntilReady(timeout: timeout);

  /// Gate: show the rewarded ad and return whether reward was earned.
  ///
  /// Returns `true`  → reward earned → caller may proceed.
  /// Returns `false` → ad skipped / failed → caller must NOT proceed.
  ///
  /// On Web / unsupported platforms returns `true` immediately.
  Future<bool> showRewardedGate({required String placement}) =>
      _impl.showRewardedGate(placement: placement);
}
