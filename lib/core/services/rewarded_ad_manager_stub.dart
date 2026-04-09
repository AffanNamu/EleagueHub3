// ---------------------------------------------------------------------------
// STUB — used on Web and any platform that does NOT support
// google_mobile_ads (e.g. desktop).
//
// Both functions are no-ops / always-pass so that:
//   • dart2js (web) compiles cleanly — no reference to google_mobile_ads
//   • Free users on web are not blocked (ads simply don't exist on web)
// ---------------------------------------------------------------------------

Future<void> preload({String placement = 'preload'}) async {
  // No-op on unsupported platforms.
}

Future<bool> showRewardedGate({required String placement}) async {
  // On web/desktop there are no ads — allow the action to proceed.
  return true;
}
