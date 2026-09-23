// ---------------------------------------------------------------------------
// Conditional export:
// - On Web (dart.library.io unavailable) → stub (no google_mobile_ads)
// - On Mobile (dart.library.io available) → real adaptive banner
//
// Same trick as rewarded_ad_manager.dart's conditional import, but as an
// `export` since AppBannerAd is used directly as a widget (`AppBannerAd()`)
// rather than through a facade class.
// ---------------------------------------------------------------------------
export 'app_banner_ad_stub.dart' if (dart.library.io) 'app_banner_ad_mobile.dart';
