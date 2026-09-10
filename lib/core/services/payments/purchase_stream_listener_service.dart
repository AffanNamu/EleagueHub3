// lib/core/services/payments/purchase_stream_listener_service.dart
//
// NEW FILE — required for iOS App Review, harmless on Android.
//
// StoreKit (iOS) redelivers any unfinished transaction on every app
// launch until it's explicitly finished via completePurchase(). The
// existing GooglePlayBillingService._purchase() method only listens to
// the purchase stream for the duration of a single purchase call, which
// is fine for a fresh purchase made while the app stays foregrounded,
// but does NOT catch:
//   - a purchase that finishes while the app was backgrounded/killed
//     mid-checkout and only reconnects on next launch
//   - restored purchases triggered via
//     GooglePlayBillingService.instance.restorePurchases()
//
// Without something listening for the ENTIRE app lifetime, those
// transactions never get finished, and on iOS specifically, the App
// Store will keep re-presenting a "complete your purchase" prompt
// indefinitely — a real, reproducible App Review rejection reason.
//
// This class does exactly one job: listen to InAppPurchase.instance
// .purchaseStream for as long as the app is alive, and hand every
// update to GooglePlayBillingService.reconcileExternalPurchase(), which
// is idempotent and safe to call even if a concurrent _purchase() call
// is also handling the same event.
//
// WIRING REQUIRED (not done automatically — this file only defines the
// service, it does not start itself):
// In your existing app_startup_service.dart, add one line to whatever
// your startup sequence already runs early, e.g.:
//
//   PurchaseStreamListenerService.instance.start();
//
// Call it once, early, alongside your other one-time startup calls
// (Firebase init, etc). Do NOT call start() more than once per app run
// — it guards against that internally, but it's still meant to be a
// single call site.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'google_play_billing_service.dart';

class PurchaseStreamListenerService {
  PurchaseStreamListenerService._();

  static final PurchaseStreamListenerService instance =
      PurchaseStreamListenerService._();

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _started = false;

  /// Starts the app-lifetime purchase stream listener. Safe to call
  /// multiple times — only the first call actually subscribes.
  void start() {
    if (_started) {
      if (kDebugMode) {
        debugPrint(
          '[PurchaseStreamListener] start() called again — already '
          'running, ignoring.',
        );
      }
      return;
    }
    _started = true;

    final iap = InAppPurchase.instance;

    _subscription = iap.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          // Only status values that mean "money actually moved, or the
          // store is telling us about a prior purchase" need
          // reconciliation. Pending/error/canceled purchases are
          // already handled (or ignored) by whichever active
          // GooglePlayBillingService._purchase() call — if any — is in
          // flight for that specific productID; this listener does not
          // need to duplicate that handling.
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            await GooglePlayBillingService.instance
                .reconcileExternalPurchase(purchase);
          }
        }
      },
      onError: (Object e) {
        if (kDebugMode) {
          debugPrint('[PurchaseStreamListener] stream error: $e');
        }
      },
    );

    if (kDebugMode) {
      debugPrint('[PurchaseStreamListener] started.');
    }
  }

  /// Only needed if you ever tear down and rebuild the app's root
  /// widget tree in a way that should stop background listening (rare
  /// — most apps never call this).
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
