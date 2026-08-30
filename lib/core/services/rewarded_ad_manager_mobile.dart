// ---------------------------------------------------------------------------
// MOBILE IMPLEMENTATION
// Compiled only on dart:io platforms (Android / iOS).
//
// Changes vs previous version:
//   • Removed setServerSideVerificationOptions() — method was removed
//     in google_mobile_ads v5.x. SSV is now configured in AdMob console.
//   • Fixed AdError → AdError is the correct type for
//     onAdFailedToShowFullScreenContent in v5.
//   • IMPLEMENTED FAIL-OPEN: Users are granted access (returns true) if ads 
//     fail to load, fail to show, or timeout, ensuring a smooth UX.
//   • ADDED PRODUCTION KEYS: Android key updated to real production Ad Unit ID.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ── Ad unit IDs ──────────────────────────────────────────────────────────────

// Your real production Android Ad Unit ID
const String _rewardedAndroid = 'ca-app-pub-9284565371998347/5830580550';
// NOTE: Still using the test key for iOS. Update this when you set up your iOS app in AdMob!
const String _rewardedIOS     = 'ca-app-pub-3940256099942544/1712485313';

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
        ? _rewardedIOS
        : _rewardedAndroid;

// ── Public API (identical signatures to stub) ─────────────────────────────────

/// True if a rewarded ad is already loaded and cached, ready to be shown
/// with no additional network/load delay.
bool get isReady => _adsSupported && _rewardedAd != null && !_isShowing;

/// Preload a rewarded ad in the background so it is ready instantly.
Future<void> preload({String placement = 'preload'}) async {
  if (!_adsSupported) return;
  await _getOrLoadRewardedAd(placement: placement);
}

/// Waits, bounded by [timeout], for a rewarded ad to finish loading —
/// WITHOUT showing it. Use this to give an in-flight preload a short
/// grace period at the moment of user intent (e.g. a double-tap) so the
/// UI isn't blocked for the full load timeout.
///
/// If the ad isn't ready by the time [timeout] elapses, this returns
/// `false`, but the underlying load keeps running in the background
/// (deduplicated via [_loadCompleter]) and will populate [_rewardedAd]
/// whenever it eventually finishes — no ad is ever shown as a side
/// effect of calling this function.
Future<bool> waitUntilReady({
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (!_adsSupported) return false;
  if (_rewardedAd != null) return true;
  if (_isShowing) return false;

  try {
    final ad = await _getOrLoadRewardedAd(placement: 'wait_until_ready')
        .timeout(timeout, onTimeout: () => null);
    return ad != null;
  } catch (_) {
    return false;
  }
}

/// Gate: show the rewarded ad and return whether the reward was earned.
///
/// Returns `true`  → reward earned (OR ad failed to load/show) → caller proceeds.
/// Returns `false` → ad actively closed/skipped by user → caller must NOT proceed.
Future<bool> showRewardedGate({required String placement}) async {
  if (!_adsSupported) return true;

  if (_isShowing) {
    // Prevent concurrent ad shows.
    return false;
  }

  final ad = await _getOrLoadRewardedAd(placement: placement);
  if (ad == null) {
    // ── FAIL-OPEN ─────────────────────────────────────────────────────────
    // Ad failed to load (e.g., no internet, no fill).
    // Silently allow the user through.
    if (kDebugMode) {
      debugPrint('[RewardedAdManager] Ad absent. Granting free pass.');
    }
    unawaited(preload(placement: '$placement:retry_after_load_fail'));
    return true; 
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

      // ── FAIL-OPEN ─────────────────────────────────────────────────────
      // The ad broke on our end, don't punish the user.
      if (!completer.isCompleted) completer.complete(true);

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
        // ── FAIL-OPEN ───────────────────────────────────────────────────
        return true; 
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
    
    // ── FAIL-OPEN ─────────────────────────────────────────────────────
    return true; 
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
