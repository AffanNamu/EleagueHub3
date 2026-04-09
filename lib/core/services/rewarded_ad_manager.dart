import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Production-ready rewarded-ad gate with:
/// - test ad unit ids (Android/iOS)
/// - load-before-show
/// - explicit handling of:
///   - onAdLoaded / onAdFailedToLoad
///   - onUserEarnedReward
///   - onAdDismissedFullScreenContent
/// - resolves `true` only if reward was earned (and ad dismissed)
class RewardedAdManager {
  RewardedAdManager._();

  static final RewardedAdManager instance = RewardedAdManager._();

  static const _loadTimeout = Duration(seconds: 15);

  // Google-provided TEST rewarded ad unit ids.
  static const String _testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedIOS =
      'ca-app-pub-3940256099942544/1712485313';

  RewardedAd? _rewardedAd;

  bool _isLoading = false;
  bool _isShowing = false;
  Completer<RewardedAd?>? _loadCompleter;

  String get _adUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _testRewardedAndroid;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _testRewardedIOS;
    }
    // Unsupported platform (e.g., desktop). Returning Android test id is fine
    // but we also short-circuit in `_adsSupported`.
    return _testRewardedAndroid;
  }

  bool get _adsSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> preload({String placement = 'preload'}) async {
    if (!_adsSupported) return;
    await _getOrLoadRewardedAd(placement: placement);
  }

  Future<bool> showRewardedGate({
    required String placement,
  }) async {
    if (!_adsSupported) {
      // Ads not supported on this platform; do not block the user.
      return true;
    }
    if (_isShowing) {
      // Prevent concurrent shows; treat as not-earned for the caller.
      return false;
    }

    final ad = await _getOrLoadRewardedAd(placement: placement);
    if (ad == null) return false;

    _isShowing = true;
    _rewardedAd = null; // RewardedAd is single-use.

    final completer = Completer<bool>();
    bool rewardEarned = false;
    bool dismissed = false;

    void tryComplete() {
      if (completer.isCompleted) return;
      if (!dismissed) return;

      // Once dismissed, only succeed if reward was earned.
      completer.complete(rewardEarned);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        dismissed = true;
        ad.dispose();
        _isShowing = false;
        tryComplete();

        // Opportunistic preload for next time.
        unawaited(preload(placement: '$placement:after_dismiss'));
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        dismissed = true;
        ad.dispose();
        _isShowing = false;

        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(preload(placement: '$placement:after_show_fail'));
      },
      onAdShowedFullScreenContent: (ad) {
        // no-op (explicitly handled for completeness)
      },
      onAdImpression: (ad) {
        // no-op
      },
      onAdClicked: (ad) {
        // no-op
      },
    );

    try {
      ad.show(
        onUserEarnedReward: (ad, reward) {
          rewardEarned = true;
          // IMPORTANT: we still wait for dismissal before completing,
          // to avoid running navigation while the ad is still visible.
          if (dismissed) {
            tryComplete();
          }
        },
      );

      // If user earns reward, it typically happens before dismissal.
      // We'll return only after dismissal.
      final ok = await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );
      return ok;
    } catch (e) {
      try {
        ad.dispose();
      } catch (_) {}
      _isShowing = false;
      return false;
    }
  }

  Future<RewardedAd?> _getOrLoadRewardedAd({
    required String placement,
  }) async {
    if (!_adsSupported) return null;

    if (_rewardedAd != null) return _rewardedAd;

    if (_isLoading && _loadCompleter != null) {
      return _loadCompleter!.future;
    }

    _isLoading = true;
    _loadCompleter = Completer<RewardedAd?>();

    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _isLoading = false;
          _rewardedAd = ad;

          // Optional server-side verification (placeholder). Keep structure.
          ad.setServerSideVerificationOptions(
            ServerSideVerificationOptions(
              customData: placement,
            ),
          );

          if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
            _loadCompleter!.complete(ad);
          }
          _loadCompleter = null;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoading = false;
          _rewardedAd = null;

          if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
            _loadCompleter!.complete(null);
          }
          _loadCompleter = null;

          if (kDebugMode) {
            debugPrint(
              '[RewardedAdManager] onAdFailedToLoad: $error (placement=$placement)',
            );
          }
        },
      ),
    );

    try {
      final ad = await (_loadCompleter!.future).timeout(
        _loadTimeout,
        onTimeout: () => null,
      );
      return ad;
    } finally {
      _isLoading = false;
    }
  }
}
