// ---------------------------------------------------------------------------
// STUB — compiled by dart2js (Web) and on unsupported platforms.
//
// Zero references to google_mobile_ads so dart2js never tries to
// resolve the package and the web build succeeds cleanly.
//
// Free users on web are not blocked because ads don't exist on web.
// ---------------------------------------------------------------------------

Future<void> preload({String placement = 'preload'}) async {
  // No-op on web / unsupported platforms.
}

Future<bool> showRewardedGate({required String placement}) async {
  // No ads on web — allow the action to proceed freely.
  return true;
}
