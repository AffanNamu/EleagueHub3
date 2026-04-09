// ---------------------------------------------------------------------------
// MOBILE ONLY — compiled on dart:io (Android / iOS)
// Never imported on Web. dart2js never sees this file.
// ---------------------------------------------------------------------------

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Initializes the Google Mobile Ads SDK.
///
/// Must be called after [WidgetsFlutterBinding.ensureInitialized()]
/// and before [runApp()].
///
/// Safe to await — [MobileAds.initialize()] completes when the SDK
/// is ready. Ad requests made before this call will queue and fire
/// after initialization completes, but it is best practice to await.
Future<void> initializeMobileAds() async {
  await MobileAds.instance.initialize();
}
