// lib/core/services/payments/google_play_billing_service.dart
//
// Full Google Play Billing implementation using the `in_app_purchase` plugin.
//
// ── Design decisions ────────────────────────────────────────────────────────
// • Only active on Android (PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling).
// • Web always falls through to Flutterwave – this class is never called there.
// • All purchases are recorded to Firestore via PaymentsService so the backend
//   can verify and activate them via the same webhook / Cloud Function pattern.
// • Subscription products use ProductType.subs; one-time products use
//   ProductType.inapp.  Both flow through the same purchase listener.
// • The caller awaits a Future<GooglePlayPurchaseResult> that resolves when
//   the purchase stream emits a terminal state (purchased / error / cancelled).
// ────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../features/master_leagues/domain/master_league_plan.dart';
import '../../config/payment_platform_config.dart';
import '../app_analytics_service.dart';
import 'google_play_billing_catalog.dart';
import 'payment_models.dart';
import 'payments_service.dart';

// ── Result type ──────────────────────────────────────────────────────────────

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

// ── Service ──────────────────────────────────────────────────────────────────

class GooglePlayBillingService {
  GooglePlayBillingService._();

  static final GooglePlayBillingService instance =
      GooglePlayBillingService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool get enabledForAndroid =>
      PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling;

  // ── Internal helpers ────────────────────────────────────────────────────

  String _uid() =>
      (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// Fetch a single product from the Play Store catalog.
  /// Returns null when the product is not found or the store is unavailable.
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
            '[GPB] queryProductDetails error: ${response.error}');
      }
      return null;
    }

    if (response.productDetails.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '[GPB] No product found for id: $productId');
      }
      return null;
    }

    return response.productDetails.first;
  }

  /// Core purchase flow.
  /// Initiates the Play Store UI and awaits the purchase stream result.
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

    // ── Check store availability ──────────────────────────────────────────
    final available = await _iap.isAvailable();
    if (!available) {
      return GooglePlayPurchaseResult.failed(
        errorMessage:
            'Google Play Store is not available on this device.',
        productId: productId,
        attemptId: attemptId,
      );
    }

    // ── Fetch product ─────────────────────────────────────────────────────
    final product =
        await _fetchProduct(productId, isSubscription: isSubscription);
    if (product == null) {
      return GooglePlayPurchaseResult.failed(
        errorMessage:
            'This product is not available in the Play Store right now. '
            'Please try again later.',
        productId: productId,
        attemptId: attemptId,
      );
    }

    // ── Initiate purchase ─────────────────────────────────────────────────
    final PurchaseParam param = PurchaseParam(productDetails: product);

    try {
      if (isSubscription) {
        await _iap.buyNonConsumable(purchaseParam: param);
      } else {
        // One-time products are consumable so they can be re-purchased.
        await _iap.buyConsumable(purchaseParam: param);
      }
    } catch (e) {
      return GooglePlayPurchaseResult.failed(
        errorMessage: _cleanError(e),
        productId: productId,
        attemptId: attemptId,
      );
    }

    // ── Wait for purchase stream result ───────────────────────────────────
    final completer = Completer<GooglePlayPurchaseResult>();
    late StreamSubscription<List<PurchaseDetails>> sub;

    sub = _iap.purchaseStream.listen(
      (purchases) async {
        if (completer.isCompleted) return;

        for (final purchase in purchases) {
          if (purchase.productID != productId) continue;

          if (purchase.status == PurchaseStatus.pending) continue;

          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            // ── Acknowledge / consume ─────────────────────────────────────
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }

            final token = purchase.verificationData.serverVerificationData;
            final orderId = purchase.purchaseID ?? '';
            final paymentId = 'gpb_${orderId.isNotEmpty ? orderId : token}';
            final now = _nowMs();

            // ── Record to Firestore ───────────────────────────────────────
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

            // ── Analytics ─────────────────────────────────────────────────
            try {
              await AppAnalyticsService.instance.logPaymentResult(
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
            final msg = purchase.error?.message ?? 'Purchase failed.';
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

    // Safety timeout – 5 minutes is enough for the Play UI.
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () async {
        await sub.cancel();
        return GooglePlayPurchaseResult.failed(
          errorMessage:
              'Purchase timed out. Please try again.',
          productId: productId,
          attemptId: attemptId,
        );
      },
    );
  }

  /// Write purchase record to Firestore.
  /// The backend Cloud Function / worker picks this up and activates
  /// the entitlement (same pattern as Flutterwave webhook).
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

    // payments/{paymentId}
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

    // Mark the attempt as success if we have one.
    if (attemptId.trim().isNotEmpty) {
      final attRef =
          _firestore.collection('payment_attempts').doc(attemptId);
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

    await batch.commit().timeout(const Duration(seconds: 20));
  }

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

  // ── Public API ──────────────────────────────────────────────────────────

  /// Purchase a league creation unlock (one-time consumable).
  Future<GooglePlayPurchaseResult> purchaseLeagueCreation({
    required String userId,
    required String leagueName,
    required String attemptId,
  }) =>
      _purchase(
        productId: GooglePlayBillingCatalog.leagueCreationUnlockId,
        attemptId: attemptId,
        flowLabel: 'league_creation',
        leagueName: leagueName,
        productType: 'league_creation',
        productSubType: 'league_creation_checkout',
        isSubscription: false,
      );

  /// Purchase a league addons pack (one-time consumable).
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

  /// Purchase a premium app subscription.
  Future<GooglePlayPurchaseResult> purchasePremiumSubscription({
    required String userId,
    required String attemptId,
  }) =>
      _purchase(
        productId: GooglePlayBillingCatalog.premiumSubscriptionId,
        attemptId: attemptId,
        flowLabel: 'premium_subscription',
        leagueName: 'Premium',
        productType: 'premium_subscription',
        productSubType: 'premium_app_access',
        isSubscription: true,
      );

  /// Purchase an organizer plan subscription.
  Future<GooglePlayPurchaseResult> purchasePlanSubscription({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
    required String userId,
    required String attemptId,
  }) {
    final productId = GooglePlayBillingCatalog.subscriptionIdForPlan(
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
      leagueName: '${plan.displayName} ${duration.displayName}',
      productType: 'plan_subscription',
      productSubType: 'plan_${plan.id}_${duration.id}',
      isSubscription: true,
    );
  }

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
