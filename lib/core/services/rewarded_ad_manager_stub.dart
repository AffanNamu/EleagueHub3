// ---------------------------------------------------------------------------
// STUB — compiled by dart2js (Web) and on unsupported platforms.
//
// Zero references to google_mobile_ads so dart2js never tries to
// resolve the package and the web build succeeds cleanly.
//
// Free users on web are not blocked because ads don't exist on web.
// ---------------------------------------------------------------------------

// Ads aren't supported on this platform, so there's nothing to wait on —
// treat the gate as always "ready" so callers never block.
bool get isReady => true;

Future<void> preload({String placement = 'preload'}) async {
  // No-op on web / unsupported platforms.
}

Future<bool> waitUntilReady({
  Duration timeout = const Duration(seconds: 4),
}) async {
  return true;
}

Future<bool> showRewardedGate({required String placement}) async {
  // No ads on web — allow the action to proceed freely.
  return true;
}
