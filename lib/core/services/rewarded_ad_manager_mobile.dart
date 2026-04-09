// ---------------------------------------------------------------------------
// MOBILE IMPLEMENTATION
// Compiled only on dart:io platforms (Android / iOS).
//
// Changes vs previous version:
//   • Removed setServerSideVerificationOptions() — method was removed
//     in google_mobile_ads v5.x. SSV is now configured in AdMob console.
//   • Fixed AdError → AdError is the correct type for
//     onAdFailedToShowFullScreenContent in v5.
//   • All other logic is unchanged and production-ready.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ── Ad unit IDs (Google-provided TEST ids) ───────────────────────────────────

const String _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
const String _testRewardedIOS     = 'ca-app-pub-3940256099942544/1712485313';

const Duration _loadTimeout = Duration(seconds: 15);

// ── Module-level singleton state ─────────────────────────────────────────────
// State lives at module scope so the conditional-import pattern works:
// the stub and mobile files expose identical top-level function signatures.

RewardedAd? _rewardedAd;
bool        _isLoading = false;
bool        _isShowing = false;

Completer<RewardedAd?>? _loadCompleter;

// ── Platform guard ────────────────────────────────────────────────────────────

bool get _adsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

String get _adUnitId =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? _testRewardedIOS
        : _testRewardedAndroid;

// ── Public API (identical signatures to stub) ─────────────────────────────────

/// Preload a rewarded ad in the background so it is ready instantly.
Future<void> preload({String placement = 'preload'}) async {
  if (!_adsSupported) return;
  await _getOrLoadRewardedAd(placement: placement);
}

/// Gate: show the rewarded ad and return whether the reward was earned.
///
/// Returns `true`  → reward earned → caller may proceed with action.
/// Returns `false` → ad not completed / failed → caller must NOT proceed.
Future<bool> showRewardedGate({required String placement}) async {
  if (!_adsSupported) return true;

  if (_isShowing) {
    // Prevent concurrent ad shows.
    return false;
  }

  final ad = await _getOrLoadRewardedAd(placement: placement);
  if (ad == null) {
    // Ad failed to load.
    // Do not silently allow — return false so caller can show a snack.
    return false;
  }

  _isShowing = true;
  _rewardedAd = null; // RewardedAd is single-use; clear cache now.

  final completer   = Completer<bool>();
  bool rewardEarned = false;
  bool dismissed    = false;

  // ── Resolution logic ──────────────────────────────────────────────────────
  // We wait for BOTH:
  //   1. onUserEarnedReward        → sets rewardEarned = true
  //   2. onAdDismissedFullScreenContent → triggers final completion
  //
  // This prevents navigating while the ad overlay is still on screen.

  void tryComplete() {
    if (completer.isCompleted) return;
    if (!dismissed) return;
    completer.complete(rewardEarned);
  }

  ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
    // ── Dismissed (watched fully or closed early) ─────────────────────────
    onAdDismissedFullScreenContent: (RewardedAd dismissedAd) {
      dismissed = true;
      dismissedAd.dispose();
      _isShowing = false;
      tryComplete();

      // Opportunistic preload for the next time.
      unawaited(preload(placement: '$placement:after_dismiss'));
    },

    // ── Failed to show (e.g. network dropped between load and show) ───────
    onAdFailedToShowFullScreenContent: (RewardedAd failedAd, AdError err) {
      dismissed = true;
      failedAd.dispose();
      _isShowing = false;

      if (kDebugMode) {
        debugPrint(
          '[RewardedAdManager] onAdFailedToShowFullScreenContent: $err '
          '(placement=$placement)',
        );
      }

      if (!completer.isCompleted) completer.complete(false);

      unawaited(preload(placement: '$placement:after_show_fail'));
    },

    // ── Informational callbacks (kept explicit for clarity) ───────────────
    onAdShowedFullScreenContent: (_) {
      if (kDebugMode) {
        debugPrint(
          '[RewardedAdManager] onAdShowedFullScreenContent '
          '(placement=$placement)',
        );
      }
    },
    onAdImpression: (_) {},
    onAdClicked:    (_) {},
  );

  try {
    ad.show(
      onUserEarnedReward: (AdWithoutView shownAd, RewardItem reward) {
        rewardEarned = true;

        if (kDebugMode) {
          debugPrint(
            '[RewardedAdManager] onUserEarnedReward: '
            '${reward.amount} ${reward.type} (placement=$placement)',
          );
        }

        // Do NOT complete here — wait for dismissal so we never navigate
        // while the ad is still visible on screen.
        if (dismissed) tryComplete();
      },
    );

    // Hard 2-minute timeout guards against callbacks that never fire
    // (extremely rare but prevents a permanent hang / memory leak).
    final earned = await completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _isShowing = false;
        if (kDebugMode) {
          debugPrint(
            '[RewardedAdManager] show() timed out (placement=$placement)',
          );
        }
        return false;
      },
    );

    return earned;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[RewardedAdManager] show() threw: $e\n$st');
    }
    try {
      ad.dispose();
    } catch (_) {}
    _isShowing = false;
    return false;
  }
}

// ── Internal loader ───────────────────────────────────────────────────────────

/// Returns a loaded [RewardedAd] or `null` if load failed / timed out.
/// Deduplicates concurrent load requests via [_loadCompleter].
Future<RewardedAd?> _getOrLoadRewardedAd({
  required String placement,
}) async {
  if (!_adsSupported) return null;

  // Return cached ad immediately if available.
  if (_rewardedAd != null) return _rewardedAd;

  // Deduplicate: if already loading, wait for the same future.
  if (_isLoading && _loadCompleter != null) {
    return _loadCompleter!.future;
  }

  _isLoading     = true;
  _loadCompleter = Completer<RewardedAd?>();

  // Keep a local reference — the module-level pointer may be nulled
  // out by a concurrent call before our timeout fires.
  final localCompleter = _loadCompleter!;

  RewardedAd.load(
    adUnitId: _adUnitId,
    request:  const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      // ── onAdLoaded ───────────────────────────────────────────────────────
      onAdLoaded: (RewardedAd ad) {
        _isLoading  = false;
        _rewardedAd = ad;

        // NOTE: setServerSideVerificationOptions() was removed in
        // google_mobile_ads v5.x. SSV custom data is now configured
        // directly in the AdMob console under the ad unit settings.

        if (kDebugMode) {
          debugPrint(
            '[RewardedAdManager] onAdLoaded (placement=$placement)',
          );
        }

        if (!localCompleter.isCompleted) localCompleter.complete(ad);
        _loadCompleter = null;
      },

      // ── onAdFailedToLoad ─────────────────────────────────────────────────
      onAdFailedToLoad: (LoadAdError error) {
        _isLoading  = false;
        _rewardedAd = null;

        if (kDebugMode) {
          debugPrint(
            '[RewardedAdManager] onAdFailedToLoad: $error '
            '(placement=$placement)',
          );
        }

        if (!localCompleter.isCompleted) localCompleter.complete(null);
        _loadCompleter = null;
      },
    ),
  );

  try {
    final ad = await localCompleter.future.timeout(
      _loadTimeout,
      onTimeout: () {
        if (kDebugMode) {
          debugPrint(
            '[RewardedAdManager] load timed out (placement=$placement)',
          );
        }
        _isLoading = false;
        return null;
      },
    );
    return ad;
  } finally {
    _isLoading = false;
  }
}
