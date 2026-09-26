// ---------------------------------------------------------------------------
// MOBILE IMPLEMENTATION
// Compiled only on dart:io platforms (Android / iOS / desktop).
// See app_banner_ad.dart for the conditional-export entry point.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_config.dart';

bool get _adsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// A standard, full-width, adaptive-height AdMob banner -- the same
/// "anchored adaptive banner" format most free mobile apps use, sized to
/// the device's own width rather than a fixed 320x50 box. Renders nothing
/// (zero-height) until an ad has actually loaded, and again if it fails to
/// load, so a no-fill / offline moment never leaves a broken placeholder
/// box on screen.
class AppBannerAd extends StatefulWidget {
  const AppBannerAd({super.key});

  @override
  State<AppBannerAd> createState() => _AppBannerAdState();
}

class _AppBannerAdState extends State<AppBannerAd> {
  BannerAd? _bannerAd;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!_adsSupported) return;

    final width = MediaQuery.of(context).size.width.truncate();
    // NOTE: intentionally NOT using getLargeAnchoredAdaptiveBannerAdSize
    // (the analyzer's suggested "replacement") -- despite the deprecation
    // message, that calls a genuinely different, visibly taller native
    // banner format (confirmed in the plugin's own source: the two
    // methods hit different platform-channel calls,
    // AdSize#getAnchoredAdaptiveBannerAdSize vs
    // AdSize#getLargeAnchoredAdaptiveBannerAdSize), not just a renamed
    // equivalent. This keeps the standard, compact adaptive banner size
    // that matches how most apps' bottom banners actually look.
    // ignore: deprecated_member_use
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      width,
    );
    if (!mounted || size == null) return;

    final ad = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          if (!mounted) {
            loadedAd.dispose();
            return;
          }
          setState(() => _bannerAd = loadedAd as BannerAd);
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (kDebugMode) {
            debugPrint('[AppBannerAd] onAdFailedToLoad: $error');
          }
          // No retry loop here on purpose -- the next time this widget
          // rebuilds fresh (e.g. the user leaves and returns to the tab
          // holding it) a new load is attempted anyway.
        },
      ),
    );

    await ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (ad == null) return const SizedBox.shrink();

    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
