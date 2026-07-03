// lib/core/services/payments/google_play_billing_service.dart

import 'dart:async';

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
  }) =>
      GooglePlayPurchaseResult._(
        success: true,
        productId: productId,
        purchaseToken: purchaseToken,
        orderId: orderId,
        provider: 'google_play_billing',
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
  }) =>
      GooglePlayPurchaseResult._(
        success: false,
        productId: productId,
        purchaseToken: purchaseToken,
        orderId: orderId,
        provider: 'google_play_billing',
        errorMessage: errorMessage,
        attemptId: attemptId,
        paymentId: paymentId,
      );
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

  // ── Badge grant on purchase success ──────────────────────────────────────

  /// Grants the appropriate badges immediately after a confirmed
  /// Google Play purchase.
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
      );
    }

    final available = await _iap.isAvailable();
    if (!available) {
      return GooglePlayPurchaseResult.failed(
        errorMessage:
            'Google Play Store is not available on this device.',
        productId: productId,
        attemptId: attemptId,
      );
    }

    final product = await _fetchProduct(
      productId,
      isSubscription: isSubscription,
    );
    if (product == null) {
      return GooglePlayPurchaseResult.failed(
        errorMessage:
            'This product is not available in the Play Store '
            'right now. Please try again later.',
        productId: productId,
        attemptId: attemptId,
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
                now: now,
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[GPB] Firestore record error: $e');
              }
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
                provider: 'google_play_billing',
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
        'provider': 'google_play_billing',
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
          'mode': 'google_play',
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
        raw.contains('userCanceled')) {
      return 'Purchase cancelled.';
    }
    if (raw.contains('BillingResponse.itemAlreadyOwned') ||
        raw.contains('itemAlreadyOwned')) {
      return 'You already own this product.';
    }
    if (raw.contains('BillingResponse.itemUnavailable') ||
        raw.contains('itemUnavailable')) {
      return 'This product is not available right now.';
    }
    if (raw.contains('SocketException') ||
        raw.contains('NetworkException')) {
      return 'Network error. Please check your connection.';
    }
    return raw;
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
              'No Play Store product is configured for '
              '${plan.displayName} ${duration.displayName}.',
          attemptId: attemptId,
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
        provider: 'google_play_billing',
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