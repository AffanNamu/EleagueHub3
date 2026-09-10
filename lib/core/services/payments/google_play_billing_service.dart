// lib/core/services/payments/google_play_billing_service.dart
//
// UPDATED: added fetchOrganizerVerificationPrice(), alongside the
// existing fetchPlanPrice(), so the organizer verification screen can
// show the REAL price Google Play will charge on Android — pulled live
// from Play Console via queryProductDetails() — instead of the
// Flutterwave/web pricing config, which is the wrong source of truth
// once Android routes payments through Google Play Billing.
//
// UPDATED AGAIN (iOS support): this class was already built entirely on
// the platform-agnostic `in_app_purchase` package APIs (InAppPurchase
// .instance, buyConsumable/buyNonConsumable, purchaseStream,
// completePurchase) — none of the purchase-flow logic was actually
// Android-Billing-Library-specific. So instead of writing a parallel
// iOS class, this file now serves BOTH platforms:
//   - the class name and every existing public method signature are
//     UNCHANGED, so no call site elsewhere in the app needs to change
//   - `_providerName` now resolves to 'app_store' on iOS instead of
//     always 'google_play_billing', so receipts/analytics correctly
//     record which store was actually charged
//   - added reconcileExternalPurchase() + restorePurchases(): required
//     for iOS App Store Review (guideline 3.1.1 — Restore Purchases
//     must exist for any non-consumable/subscription IAP; StoreKit also
//     redelivers unfinished transactions on every app launch, which
//     must be finished or the purchase sheet nags the user forever).
//     See purchase_stream_listener_service.dart for the app-level
//     listener that calls reconcileExternalPurchase().
import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../features/master_leagues/domain/master_league_plan.dart';
import '../../../features/verification/logic/badge_service.dart';
import '../../config/payment_platform_config.dart';
import '../app_analytics_service.dart';
import 'google_play_billing_catalog.dart';
import 'payment_models.dart';
import 'payments_service.dart';

// ── Result ────────────────────────────────────────────────────────────────────

class GooglePlayPurchaseResult {
  final bool success;
  final String productId;
  final String purchaseToken;
  final String orderId;
  final String provider;
  final String? errorMessage;
  final String attemptId;
  final String paymentId;

  const GooglePlayPurchaseResult._({
    required this.success,
    required this.productId,
    required this.purchaseToken,
    required this.orderId,
    required this.provider,
    required this.errorMessage,
    required this.attemptId,
    required this.paymentId,
  });

  factory GooglePlayPurchaseResult.paid({
    required String productId,
    required String purchaseToken,
    required String orderId,
    String attemptId = '',
    String paymentId = '',
    String provider = 'google_play_billing',
  }) =>
      GooglePlayPurchaseResult._(
        success: true,
        productId: productId,
        purchaseToken: purchaseToken,
        orderId: orderId,
        provider: provider,
        errorMessage: null,
        attemptId: attemptId,
        paymentId: paymentId,
      );

  factory GooglePlayPurchaseResult.failed({
    required String errorMessage,
    String productId = '',
    String purchaseToken = '',
    String orderId = '',
    String attemptId = '',
    String paymentId = '',
    String provider = 'google_play_billing',
  }) =>
      GooglePlayPurchaseResult._(
        success: false,
        productId: productId,
        purchaseToken: purchaseToken,
        orderId: orderId,
        provider: provider,
        errorMessage: errorMessage,
        attemptId: attemptId,
        paymentId: paymentId,
      );
}

// ── Price info ───────────────────────────────────────────────────────────────
//
// A thin wrapper around what queryProductDetails() gives us for a given
// product. `formattedPrice` is the exact string the store will show at
// checkout (already localized — e.g. "$4.99", "₦4,500.00", "€4.49" —
// using whatever you configured in Play Console / App Store Connect for
// that user's store country).

class PlayPlanPriceInfo {
  final String formattedPrice;
  final String currencyCode;
  final double rawPrice;

  const PlayPlanPriceInfo({
    required this.formattedPrice,
    required this.currencyCode,
    required this.rawPrice,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class GooglePlayBillingService {
  GooglePlayBillingService._();

  static final GooglePlayBillingService instance =
      GooglePlayBillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool get enabledForAndroid =>
      PaymentPlatformConfig
          .routeAndroidPaymentsToGooglePlayBilling;

  /// NEW: true when this platform should use native in-app purchase at
  /// all — Google Play Billing on Android OR StoreKit on iOS. Prefer
  /// this in new code; enabledForAndroid is kept for existing call
  /// sites that only ever checked Android.
  bool get enabledForInAppPurchase =>
      PaymentPlatformConfig.useNativeInAppPurchase;

  /// NEW: which store is actually processing the purchase on this
  /// platform. Used to tag results/receipts/analytics correctly instead
  /// of always writing 'google_play_billing' even when the charge went
  /// through the App Store.
  String get _providerName =>
      Platform.isIOS ? 'app_store' : 'google_play_billing';

  // ── Internal helpers ──────────────────────────────────────────────────────

  String _uid() =>
      (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Future<ProductDetails?> _fetchProduct(
    String productId, {
    bool isSubscription = false,
  }) async {
    final available = await _iap.isAvailable();
    if (!available) return null;

    final Set<String> ids = {productId};
    final ProductDetailsResponse response =
        await _iap.queryProductDetails(ids);

    if (response.error != null) {
      if (kDebugMode) {
        debugPrint(
          '[GPB] queryProductDetails error: ${response.error}',
        );
      }
      return null;
    }

    if (response.productDetails.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[GPB] No product found for id: $productId',
        );
      }
      return null;
    }

    return response.productDetails.first;
  }

  // ── Live pricing (display-only, no charge) ───────────────────────────────
  //
  // Fetches the real, current price the store has configured for this
  // plan+duration's subscription product, for THIS user's store
  // account/country. This is exactly the price _purchase() will end up
  // charging — there is no separate "display price" source of truth
  // anymore for native-IAP users.
  //
  // Returns null if the store is unavailable, the product doesn't
  // exist / isn't published for this plan+duration, or the query fails
  // — callers should treat null as "price unavailable right now" and
  // fall back gracefully (e.g. show a loading/placeholder state and
  // let the actual purchase call surface any real error).
  Future<PlayPlanPriceInfo?> fetchPlanPrice({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
  }) async {
    final productId = GooglePlayBillingCatalog.subscriptionIdForPlan(
      plan: plan,
      duration: duration,
    );

    if (productId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[GPB] fetchPlanPrice: no product configured for '
          '${plan.id}/${duration.id}',
        );
      }
      return null;
    }

    final product = await _fetchProduct(productId, isSubscription: true);
    if (product == null) return null;

    return PlayPlanPriceInfo(
      formattedPrice: product.price,
      currencyCode: product.currencyCode,
      rawPrice: product.rawPrice,
    );
  }

  // ── Live pricing for organizer verification ───────────────────────────
  //
  // Same mechanism as fetchPlanPrice() above, applied to the
  // organizer_verification / organizer_verification_renewal one-time
  // products. Falls back to null under the same conditions as
  // fetchPlanPrice(); callers should fall back to RemotePricingService
  // in that case (e.g. non-native-IAP platform, or the store product
  // genuinely isn't available).
  Future<PlayPlanPriceInfo?> fetchOrganizerVerificationPrice({
    bool isRenewal = false,
  }) async {
    final productId = isRenewal
        ? GooglePlayBillingCatalog.organizerVerificationRenewalId
        : GooglePlayBillingCatalog.organizerVerificationId;

    final product = await _fetchProduct(productId, isSubscription: false);
    if (product == null) return null;

    return PlayPlanPriceInfo(
      formattedPrice: product.price,
      currencyCode: product.currencyCode,
      rawPrice: product.rawPrice,
    );
  }

  // ── Badge grant on purchase success ──────────────────────────────────────

  /// Grants the appropriate badges immediately after a confirmed
  /// native-IAP purchase (Play Billing or StoreKit).
  ///
  /// This client-side grant runs before the server-side webhook so
  /// that the UI reflects the new badge state without waiting for
  /// the webhook. Both writes are idempotent — running twice is safe.
  ///
  /// Errors are caught and logged; they must never propagate back
  /// to the purchase flow.
  Future<void> _grantBadgesForProduct({
    required String productId,
  }) async {
    final uid = _uid();
    if (uid.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[GPB] _grantBadgesForProduct: no authenticated user '
          '— skipping badge grant.',
        );
      }
      return;
    }

    try {
      // ── Plan subscriptions ───────────────────────────────────────────
      final tierInfo =
          GooglePlayBillingCatalog.tierInfoForProductId(productId);

      if (tierInfo != null) {
        final expiresAt = DateTime.now()
            .add(Duration(days: tierInfo.durationDays));

        switch (tierInfo.tier) {
          case PlanSubscriptionTier.pro:
            await BadgeService.instance
                .onProSubscriptionPurchased(
              userId: uid,
              expiresAt: expiresAt,
            );
            if (kDebugMode) {
              debugPrint(
                '[GPB] Pro subscription badges granted '
                'for $uid (expires $expiresAt)',
              );
            }
            return;

          case PlanSubscriptionTier.elite:
            await BadgeService.instance
                .onEliteSubscriptionPurchased(
              userId: uid,
              expiresAt: expiresAt,
            );
            if (kDebugMode) {
              debugPrint(
                '[GPB] Elite subscription badges granted '
                'for $uid (expires $expiresAt)',
              );
            }
            return;
        }
      }

      // ── Organizer verification (initial) ─────────────────────────────
      if (productId ==
          GooglePlayBillingCatalog.organizerVerificationId) {
        await BadgeService.instance
            .onOrganizerVerificationPurchased(userId: uid);
        if (kDebugMode) {
          debugPrint(
            '[GPB] Organizer verification badge granted for $uid',
          );
        }
        return;
      }

      // ── Organizer verification renewal ───────────────────────────────
      if (productId ==
          GooglePlayBillingCatalog
              .organizerVerificationRenewalId) {
        await BadgeService.instance
            .onOrganizerVerificationRenewalPurchased(
          userId: uid,
        );
        if (kDebugMode) {
          debugPrint(
            '[GPB] Organizer verification renewal badge '
            'granted for $uid',
          );
        }
        return;
      }

      // Product has no badge mapping — expected for league products.
      if (kDebugMode) {
        debugPrint(
          '[GPB] _grantBadgesForProduct: productId=$productId '
          'has no badge mapping — skipped.',
        );
      }
    } catch (e) {
      // Badge grant failure must never fail the purchase flow.
      if (kDebugMode) {
        debugPrint(
          '[GPB] _grantBadgesForProduct error '
          'for productId=$productId: $e',
        );
      }
    }
  }

  // ── Core purchase flow ────────────────────────────────────────────────────

  Future<GooglePlayPurchaseResult> _purchase({
    required String productId,
    required String attemptId,
    required String flowLabel,
    required String leagueName,
    required String productType,
    required String productSubType,
    bool isSubscription = false,
  }) async {
    final uid = _uid();
    if (uid.isEmpty) {
      return GooglePlayPurchaseResult.failed(
        errorMessage: 'Please sign in to continue.',
        productId: productId,
        attemptId: attemptId,
        provider: _providerName,
      );
    }

    final available = await _iap.isAvailable();
    if (!available) {
      return GooglePlayPurchaseResult.failed(
        errorMessage: Platform.isIOS
            ? 'The App Store is not available on this device.'
            : 'Google Play Store is not available on this device.',
        productId: productId,
        attemptId: attemptId,
        provider: _providerName,
      );
    }

    final product = await _fetchProduct(
      productId,
      isSubscription: isSubscription,
    );
    if (product == null) {
      return GooglePlayPurchaseResult.failed(
        errorMessage: Platform.isIOS
            ? 'This product is not available in the App Store '
                'right now. Please try again later.'
            : 'This product is not available in the Play Store '
                'right now. Please try again later.',
        productId: productId,
        attemptId: attemptId,
        provider: _providerName,
      );
    }

    final PurchaseParam param =
        PurchaseParam(productDetails: product);

    try {
      if (isSubscription) {
        await _iap.buyNonConsumable(purchaseParam: param);
      } else {
        await _iap.buyConsumable(purchaseParam: param);
      }
    } catch (e) {
      return GooglePlayPurchaseResult.failed(
        errorMessage: _cleanError(e),
        productId: productId,
        attemptId: attemptId,
        provider: _providerName,
      );
    }

    final completer = Completer<GooglePlayPurchaseResult>();
    late StreamSubscription<List<PurchaseDetails>> sub;

    sub = _iap.purchaseStream.listen(
      (purchases) async {
        if (completer.isCompleted) return;

        for (final purchase in purchases) {
          if (purchase.productID != productId) continue;

          if (purchase.status == PurchaseStatus.pending) {
            continue;
          }

          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }

            final token = purchase
                .verificationData.serverVerificationData;
            final orderId = purchase.purchaseID ?? '';
            final paymentId =
                'gpb_${orderId.isNotEmpty ? orderId : token}';
            final now = _nowMs();

            // ── Persist receipt ───────────────────────────────────────
            // Retry once (covers transient network blips, which is the
            // common case right after a purchase sheet closes), and if
            // it still fails, report FAILURE instead of success. The
            // purchase itself is already completed/finished at this
            // point and can't be "undone" here, so the failure message
            // points the user back at the original flow (the store
            // won't double-charge for an owned/consumed purchase) and
            // includes the order id for support escalation as a
            // fallback.
            bool receiptPersisted = false;
            try {
              await _recordGooglePlayPurchase(
                uid: uid,
                productId: productId,
                purchaseToken: token,
                orderId: orderId,
                paymentId: paymentId,
                attemptId: attemptId,
                productType: productType,
                productSubType: productSubType,
                leagueName: leagueName,
                provider: _providerName,
                now: now,
              );
              receiptPersisted = true;
            } catch (e) {
              if (kDebugMode) {
                debugPrint(
                  '[GPB] Firestore record error (attempt 1): $e',
                );
              }
              try {
                await Future<void>.delayed(const Duration(seconds: 2));
                await _recordGooglePlayPurchase(
                  uid: uid,
                  productId: productId,
                  purchaseToken: token,
                  orderId: orderId,
                  paymentId: paymentId,
                  attemptId: attemptId,
                  productType: productType,
                  productSubType: productSubType,
                  leagueName: leagueName,
                  provider: _providerName,
                  now: now,
                );
                receiptPersisted = true;
              } catch (e2) {
                if (kDebugMode) {
                  debugPrint(
                    '[GPB] Firestore record error (attempt 2): $e2',
                  );
                }
              }
            }

            if (!receiptPersisted) {
              try {
                await AppAnalyticsService.instance.logPaymentResult(
                  kind: flowLabel,
                  leagueId: '',
                  leagueName: leagueName,
                  success: false,
                  provider: _providerName,
                  currency: 'PLAY',
                  amount: '',
                  receiptId: orderId,
                  errorMessage: 'receipt_persist_failed',
                  userId: uid,
                );
              } catch (_) {}

              await sub.cancel();
              completer.complete(
                GooglePlayPurchaseResult.failed(
                  errorMessage:
                      'Your purchase completed with the store, but '
                      'we couldn\'t save the receipt to your account. '
                      'Please check your connection and try again -- '
                      'you won\'t be charged twice for an already-owned '
                      'purchase. If this keeps happening, contact '
                      'support with order '
                      '${orderId.isNotEmpty ? orderId : token}.',
                  productId: productId,
                  purchaseToken: token,
                  orderId: orderId,
                  attemptId: attemptId,
                  paymentId: paymentId,
                  provider: _providerName,
                ),
              );
              return;
            }

            // ── Grant badges ──────────────────────────────────────────
            // Called after receipt is persisted. Errors are caught
            // internally — they never block the purchase result.
            await _grantBadgesForProduct(productId: productId);

            // ── Analytics ─────────────────────────────────────────────
            try {
              await AppAnalyticsService.instance
                  .logPaymentResult(
                kind: flowLabel,
                leagueId: '',
                leagueName: leagueName,
                success: true,
                provider: _providerName,
                currency: 'PLAY',
                amount: '',
                receiptId: orderId,
                errorMessage: null,
                userId: uid,
              );
            } catch (_) {}

            await sub.cancel();
            completer.complete(
              GooglePlayPurchaseResult.paid(
                productId: productId,
                purchaseToken: token,
                orderId: orderId,
                attemptId: attemptId,
                paymentId: paymentId,
                provider: _providerName,
              ),
            );
            return;
          }

          if (purchase.status == PurchaseStatus.error) {
            final msg =
                purchase.error?.message ?? 'Purchase failed.';
            await sub.cancel();
            completer.complete(
              GooglePlayPurchaseResult.failed(
                errorMessage: msg,
                productId: productId,
                attemptId: attemptId,
                provider: _providerName,
              ),
            );
            return;
          }

          if (purchase.status == PurchaseStatus.canceled) {
            await sub.cancel();
            completer.complete(
              GooglePlayPurchaseResult.failed(
                errorMessage: 'Purchase cancelled.',
                productId: productId,
                attemptId: attemptId,
                provider: _providerName,
              ),
            );
            return;
          }
        }
      },
      onError: (Object e) async {
        if (completer.isCompleted) return;
        await sub.cancel();
        completer.complete(
          GooglePlayPurchaseResult.failed(
            errorMessage: _cleanError(e),
            productId: productId,
            attemptId: attemptId,
            provider: _providerName,
          ),
        );
      },
    );

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () async {
        await sub.cancel();
        return GooglePlayPurchaseResult.failed(
          errorMessage: 'Purchase timed out. Please try again.',
          productId: productId,
          attemptId: attemptId,
          provider: _providerName,
        );
      },
    );
  }

  // ── Receipt persistence ───────────────────────────────────────────────────

  Future<void> _recordGooglePlayPurchase({
    required String uid,
    required String productId,
    required String purchaseToken,
    required String orderId,
    required String paymentId,
    required String attemptId,
    required String productType,
    required String productSubType,
    required String leagueName,
    required int now,
    String provider = 'google_play_billing',
  }) async {
    final batch = _firestore.batch();

    final payRef =
        _firestore.collection('payments').doc(paymentId);
    batch.set(
      payRef,
      <String, dynamic>{
        'paymentId': paymentId,
        'attemptId': attemptId,
        'status': 'success',
        'provider': provider,
        'providerTransactionId': orderId,
        'purchaseToken': purchaseToken,
        'productId': productId,
        'productType': productType,
        'productSubType': productSubType,
        'receiptId': orderId,
        'userId': uid,
        'leagueName': leagueName,
        'leagueId': '',
        'currency': 'PLAY',
        'amount': 0,
        'amountStr': '',
        'paidAtMs': now,
        'createdAtMs': now,
        'updatedAtMs': now,
        'verification': <String, dynamic>{
          'mode': provider,
          'verified': false,
          'needsServerVerification': true,
        },
      },
      SetOptions(merge: false),
    );

    if (attemptId.trim().isNotEmpty) {
      final attRef = _firestore
          .collection('payment_attempts')
          .doc(attemptId);
      batch.set(
        attRef,
        <String, dynamic>{
          'status': 'client_success',
          'paymentId': paymentId,
          'receiptId': orderId,
          'providerTransactionId': orderId,
          'purchaseToken': purchaseToken,
          'paidAtMs': now,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );
    }

    await batch
        .commit()
        .timeout(const Duration(seconds: 20));
  }

  // ── Error normaliser ──────────────────────────────────────────────────────

  String _cleanError(Object e) {
    final raw = e.toString().trim();
    if (raw.contains('BillingResponse.userCanceled') ||
        raw.contains('userCanceled') ||
        raw.contains('storeKitError.userCancelled') ||
        raw.contains('paymentCancelled')) {
      return 'Purchase cancelled.';
    }
    if (raw.contains('BillingResponse.itemAlreadyOwned') ||
        raw.contains('itemAlreadyOwned')) {
      return 'You already own this product.';
    }
    if (raw.contains('BillingResponse.itemUnavailable') ||
        raw.contains('itemUnavailable') ||
        raw.contains('storeProductNotAvailable')) {
      return 'This product is not available right now.';
    }
    if (raw.contains('SocketException') ||
        raw.contains('NetworkException')) {
      return 'Network error. Please check your connection.';
    }
    return raw;
  }

  // ── NEW: Restore / reconcile (required for iOS App Review) ──────────────

  /// Triggers the platform purchase-restore flow. Required by Apple
  /// guideline 3.1.1 for any app selling non-consumables/subscriptions
  /// — there must be a visible "Restore Purchases" control somewhere in
  /// the app (e.g. upgrade_plan_screen.dart) that calls this. Also
  /// works on Android, where it's not mandatory but harmless.
  ///
  /// Restored purchases arrive asynchronously via the same
  /// purchaseStream and are finished/recorded by
  /// reconcileExternalPurchase() below — this method itself does not
  /// wait for or return that outcome, it only kicks off the
  /// platform-native restore flow. Pair it with the app-level listener
  /// in purchase_stream_listener_service.dart.
  Future<void> restorePurchases() => _iap.restorePurchases();

  /// Finishes and records a restored/leftover transaction that isn't
  /// already being handled by an in-flight purchaseLeagueCreation() /
  /// purchasePlanSubscription() / etc. call.
  ///
  /// Call this from a global/app-level purchase stream listener set up
  /// once at app startup (see purchase_stream_listener_service.dart).
  /// This covers two real StoreKit/Play Billing situations the
  /// per-call listener inside _purchase() above cannot: (1) StoreKit
  /// redelivers unfinished transactions on every app launch — if
  /// nothing outside an active _purchase() call is listening, those
  /// transactions never get finished and the store's payment sheet
  /// nags the user indefinitely; (2) the user taps "Restore Purchases"
  /// via restorePurchases() above, which is not tied to any specific
  /// in-flight _purchase() call.
  ///
  /// Safe to call multiple times for the same purchase —
  /// completePurchase() is a no-op if already finished, and the
  /// Firestore write uses a deterministic paymentId so re-writing it is
  /// harmless.
  Future<void> reconcileExternalPurchase(PurchaseDetails purchase) async {
    final uid = _uid();
    if (uid.isEmpty) return;

    try {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }

      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        return;
      }

      final productId = purchase.productID;
      final token = purchase.verificationData.serverVerificationData;
      final orderId = purchase.purchaseID ?? '';
      final paymentId = 'gpb_${orderId.isNotEmpty ? orderId : token}';
      final now = _nowMs();

      await _recordGooglePlayPurchase(
        uid: uid,
        productId: productId,
        purchaseToken: token,
        orderId: orderId,
        paymentId: paymentId,
        attemptId: '',
        productType: 'restored_purchase',
        productSubType: 'app_launch_reconciliation',
        leagueName: '',
        provider: _providerName,
        now: now,
      );

      await _grantBadgesForProduct(productId: productId);

      if (kDebugMode) {
        debugPrint(
          '[GPB] Reconciled external/restored purchase: $productId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GPB] reconcileExternalPurchase error: $e');
      }
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// League creation unlock — one-time consumable.
  Future<GooglePlayPurchaseResult> purchaseLeagueCreation({
    required String userId,
    required String leagueName,
    required String attemptId,
  }) =>
      _purchase(
        productId:
            GooglePlayBillingCatalog.leagueCreationUnlockId,
        attemptId: attemptId,
        flowLabel: 'league_creation',
        leagueName: leagueName,
        productType: 'league_creation',
        productSubType: 'league_creation_checkout',
        isSubscription: false,
      );

  /// League addons pack — one-time consumable.
  Future<GooglePlayPurchaseResult> purchaseLeagueAddons({
    required String userId,
    required String leagueName,
    required String attemptId,
  }) =>
      _purchase(
        productId: GooglePlayBillingCatalog.leagueAddonsPackId,
        attemptId: attemptId,
        flowLabel: 'league_upgrade',
        leagueName: leagueName,
        productType: 'league_upgrade',
        productSubType: 'league_addons_only',
        isSubscription: false,
      );

  /// Premium app subscription.
  Future<GooglePlayPurchaseResult> purchasePremiumSubscription({
    required String userId,
    required String attemptId,
  }) =>
      _purchase(
        productId:
            GooglePlayBillingCatalog.premiumSubscriptionId,
        attemptId: attemptId,
        flowLabel: 'premium_subscription',
        leagueName: 'Premium',
        productType: 'premium_subscription',
        productSubType: 'premium_app_access',
        isSubscription: true,
      );

  /// Organizer plan subscription.
  Future<GooglePlayPurchaseResult> purchasePlanSubscription({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
    required String userId,
    required String attemptId,
  }) {
    final productId =
        GooglePlayBillingCatalog.subscriptionIdForPlan(
      plan: plan,
      duration: duration,
    );

    if (productId.isEmpty) {
      return Future.value(
        GooglePlayPurchaseResult.failed(
          errorMessage:
              'No store product is configured for '
              '${plan.displayName} ${duration.displayName}.',
          attemptId: attemptId,
          provider: _providerName,
        ),
      );
    }

    return _purchase(
      productId: productId,
      attemptId: attemptId,
      flowLabel: 'plan_subscription',
      leagueName:
          '${plan.displayName} ${duration.displayName}',
      productType: 'plan_subscription',
      productSubType: 'plan_${plan.id}_${duration.id}',
      isSubscription: true,
    );
  }

  /// Organizer verification — one-time consumable.
  Future<GooglePlayPurchaseResult>
      purchaseOrganizerVerification({
    required String userId,
    required String masterLeagueName,
    required String attemptId,
  }) =>
          _purchase(
            productId:
                GooglePlayBillingCatalog.organizerVerificationId,
            attemptId: attemptId,
            flowLabel: 'organizer_verification',
            leagueName: masterLeagueName,
            productType: 'organizer_verification',
            productSubType:
                'master_league_organizer_verification',
            isSubscription: false,
          );

  /// Organizer verification renewal — one-time consumable.
  Future<GooglePlayPurchaseResult>
      purchaseOrganizerVerificationRenewal({
    required String userId,
    required String masterLeagueName,
    required String attemptId,
  }) =>
          _purchase(
            productId: GooglePlayBillingCatalog
                .organizerVerificationRenewalId,
            attemptId: attemptId,
            flowLabel: 'organizer_verification_renewal',
            leagueName: masterLeagueName,
            productType: 'organizer_verification_renewal',
            productSubType:
                'master_league_organizer_verification_renewal',
            isSubscription: false,
          );

  /// Create a Firestore payment attempt and return the attempt id.
  Future<String> createAttempt({
    required String userId,
    required String productId,
    required String productType,
    required String productSubType,
    required String leagueName,
    String planId = '',
    String planDurationId = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    return PaymentsService.instance.createAttempt(
      PaymentAttemptCreate(
        provider: _providerName,
        currency: 'PLAY',
        amount: 0,
        amountStr: '',
        userId: userId,
        leagueId: '',
        leagueName: leagueName,
        productType: productType,
        productSubType: productSubType,
        planId: planId,
        planDurationId: planDurationId,
        metadata: metadata,
        items: [
          PaymentLineItem(
            productType: productType,
            productSubType: productSubType,
            quantity: 1,
            amount: 0,
          ),
        ],
      ),
    );
  }
}
