// ---------------------------------------------------------------------------
// MOBILE IMPLEMENTATION — compiled only on dart:io platforms (Android / iOS).
// This file directly references google_mobile_ads types.
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// ─── Ad unit IDs ────────────────────────────────────────────────────────────

const String _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
const String _testRewardedIOS     = 'ca-app-pub-3940256099942544/1712485313';

const Duration _loadTimeout = Duration(seconds: 15);

// ─── Module-level singleton state ───────────────────────────────────────────
// We keep state at module level (not inside a class) so that the conditional
// import pattern works cleanly — the stub and mobile files expose the same
// top-level function signatures.

RewardedAd? _rewardedAd;
bool        _isLoading  = false;
bool        _isShowing  = false;

Completer<RewardedAd?>? _loadCompleter;

// ─── Platform helpers ────────────────────────────────────────────────────────

bool get _adsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
     defaultTargetPlatform == TargetPlatform.iOS);

String get _adUnitId {
  if (defaultTargetPlatform == TargetPlatform.iOS) return _testRewardedIOS;
  return _testRewardedAndroid;
}

// ─── Public API (matches stub signatures) ────────────────────────────────────

/// Preload a rewarded ad in the background so it is ready instantly.
Future<void> preload({String placement = 'preload'}) async {
  if (!_adsSupported) return;
  await _getOrLoadRewardedAd(placement: placement);
}

/// Gate: show the rewarded ad and return whether the reward was earned.
///
/// Returns `true`  → reward earned, caller may proceed with the action.
/// Returns `false` → ad not completed / failed, caller must NOT proceed.
Future<bool> showRewardedGate({required String placement}) async {
  if (!_adsSupported) {
    // Platform does not support ads — let the user through.
    return true;
  }

  if (_isShowing) {
    // Prevent concurrent ad shows.
    return false;
  }

  final ad = await _getOrLoadRewardedAd(placement: placement);
  if (ad == null) {
    // Ad failed to load — do not block the user silently failing an ad
    // should not punish the user; return false so the caller can show
    // a snack and let them retry, matching the stated UX requirement.
    return false;
  }

  _isShowing = true;
  _rewardedAd = null; // RewardedAd is single-use; clear cache now.

  final completer  = Completer<bool>();
  bool rewardEarned = false;
  bool dismissed    = false;

  // ── Resolve the gate ──────────────────────────────────────────────────────
  // We wait for BOTH events:
  //   1. onUserEarnedReward  → sets rewardEarned = true
  //   2. onAdDismissedFullScreenContent → triggers completion
  //
  // This prevents navigating while the ad is still on screen.

  void tryComplete() {
    if (completer.isCompleted) return;
    if (!dismissed) return;
    completer.complete(rewardEarned);
  }

  ad.fullScreenContentCallback = FullScreenContentCallback(
    // ── Ad dismissed (user closed it after watching or skipped) ──────────
    onAdDismissedFullScreenContent: (RewardedAd closedAd) {
      dismissed = true;
      closedAd.dispose();
      _isShowing = false;
      tryComplete();

      // Preload the next ad in the background.
      unawaited(preload(placement: '$placement:after_dismiss'));
    },

    // ── Ad failed to show (e.g. network dropped between load and show) ───
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

    // ── No-ops — included for explicitness ───────────────────────────────
    onAdShowedFullScreenContent: (_) {},
    onAdImpression:              (_) {},
    onAdClicked:                 (_) {},
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
        // Do NOT complete here — wait for dismissal so we do not navigate
        // while the ad is still visible on screen.
        if (dismissed) tryComplete();
      },
    );

    // Wait for dismissal (or hard timeout of 2 minutes in case callbacks
    // are never fired — extremely rare but guards against memory leaks).
    final earned = await completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _isShowing = false;
        return false;
      },
    );
    return earned;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[RewardedAdManager] show() threw: $e\n$st');
    }
    try { ad.dispose(); } catch (_) {}
    _isShowing = false;
    return false;
  }
}

// ─── Internal loader ──────────────────────────────────────────────────────────

/// Returns a loaded [RewardedAd] or `null` if load failed / timed out.
///
/// Deduplicates concurrent load requests via [_loadCompleter].
Future<RewardedAd?> _getOrLoadRewardedAd({
  required String placement,
}) async {
  if (!_adsSupported) return null;

  // Return cached ad if available.
  if (_rewardedAd != null) return _rewardedAd;

  // Deduplicate: if already loading, wait for the same future.
  if (_isLoading && _loadCompleter != null) {
    return _loadCompleter!.future;
  }

  _isLoading     = true;
  _loadCompleter = Completer<RewardedAd?>();

  // Keep a local reference — the module-level one may be nulled out by the
  // time the timeout fires.
  final localCompleter = _loadCompleter!;

  RewardedAd.load(
    adUnitId: _adUnitId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      // ── onAdLoaded ────────────────────────────────────────────────────
      onAdLoaded: (RewardedAd ad) {
        _isLoading  = false;
        _rewardedAd = ad;

        // Optional: server-side verification so your backend can validate
        // the reward server-to-server (SSV). The `customData` field is
        // used to tag which placement earned the reward.
        ad.setServerSideVerificationOptions(
          ServerSideVerificationOptions(
            customData: placement,
          ),
        );

        if (kDebugMode) {
          debugPrint(
            '[RewardedAdManager] onAdLoaded (placement=$placement)',
          );
        }

        if (!localCompleter.isCompleted) localCompleter.complete(ad);
        _loadCompleter = null;
      },

      // ── onAdFailedToLoad ──────────────────────────────────────────────
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
        return null;
      },
    );
    return ad;
  } finally {
    _isLoading = false;
  }
}
