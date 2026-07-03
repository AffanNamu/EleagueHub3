// lib/features/master_leagues/logic/master_league_payment_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/config/payment_platform_config.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/payments/google_play_billing_catalog.dart';
import '../../../core/services/payments/google_play_billing_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/payments/payments_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../features/verification/logic/badge_service.dart';
import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';
import 'master_league_pricing_service.dart';

// ── Result ────────────────────────────────────────────────────────────────────

class MasterLeaguePaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;
  final String currency;
  final String totalAmount;
  final String attemptId;
  final String paymentId;
  final String transactionId;
  final String txRef;

  const MasterLeaguePaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.currency,
    required this.totalAmount,
    required this.attemptId,
    required this.paymentId,
    required this.transactionId,
    required this.txRef,
  });

  factory MasterLeaguePaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required String currency,
    required String totalAmount,
    required String attemptId,
    required String paymentId,
    required String transactionId,
    required String txRef,
  }) {
    return MasterLeaguePaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
      currency: currency,
      totalAmount: totalAmount,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }

  factory MasterLeaguePaymentResult.failed({
    required String provider,
    required String errorMessage,
    String currency = '',
    String totalAmount = '0',
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) {
    return MasterLeaguePaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
      currency: currency,
      totalAmount: totalAmount,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }
}

// ── Abstract contract ─────────────────────────────────────────────────────────

abstract class MasterLeaguePaymentService {
  Future<MasterLeaguePaymentResult> payForPlanSubscription({
    required BuildContext context,
    required String userId,
    required MasterLeaguePlan plan,
    required PlanDuration duration,
  });

  Future<MasterLeaguePaymentResult> payForOrganizerVerification({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  });

  Future<MasterLeaguePaymentResult>
      payForOrganizerVerificationRenewal({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  });

  String get providerName;
}

// ── Implementation ────────────────────────────────────────────────────────────

class FlutterwaveMasterLeaguePaymentService
    implements MasterLeaguePaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName =>
      PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling
          ? 'google_play_billing'
          : 'flutterwave';

  // ── Shared helpers ────────────────────────────────────────────────────────

  Locale _effectiveLocale(BuildContext context) {
    final base = Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;
    final forced =
        FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) {
      return Locale(
        base.languageCode.isNotEmpty ? base.languageCode : 'en',
        forced,
      );
    }
    return base;
  }

  String _paymentOptionsForCurrency(String currency) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return 'card,ussd,banktransfer';
    return 'card';
  }

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  double _roundMoney(String currency, double v) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return v.roundToDouble();
    return double.parse(v.toStringAsFixed(2));
  }

  String _resolveEffectiveUserId(String userId) {
    final u = userId.trim();
    if (u.isNotEmpty) return u;
    final authUid =
        FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.trim().isNotEmpty) return authUid.trim();
    return 'anonymous';
  }

  bool _isChargeSuccessful(ChargeResponse response) {
    final status =
        (response.status ?? '').toString().trim().toLowerCase();
    return response.success == true || status == 'successful';
  }

  String _cleanErrorMessage(Object error) {
    final raw = error.toString().trim();
    if (raw.contains(
        'Payment verification endpoint was not found (404)')) {
      return 'Payment verification service is not available right now. '
          'Please contact support or try again later.';
    }
    if (raw.contains('Payment verification failed (404)')) {
      return 'Payment verification service is not available right now. '
          'Please contact support or try again later.';
    }
    if (raw.contains('Bad state:')) {
      return raw.replaceFirst('Bad state:', '').trim();
    }
    if (raw.contains('SocketException')) {
      return 'Network error while verifying payment. '
          'Please check your internet and try again.';
    }
    if (raw.contains('timed out')) {
      return 'Payment verification timed out. Please try again.';
    }
    return raw;
  }

  // ── Badge grant helpers ───────────────────────────────────────────────────

  /// Grants plan badges (Green for Pro, Green + Organizer for Elite)
  /// after a successful plan subscription purchase.
  Future<void> _grantPlanBadges({
    required String userId,
    required MasterLeaguePlan plan,
    required PlanDuration duration,
  }) async {
    if (userId.trim().isEmpty) return;

    try {
      final expiresAt =
          DateTime.now().add(Duration(days: duration.days));

      if (plan == MasterLeaguePlan.elite) {
        await BadgeService.instance.onEliteSubscriptionPurchased(
          userId: userId,
          expiresAt: expiresAt,
        );
        if (kDebugMode) {
          debugPrint(
            '[MasterLeaguePayment] Elite badges granted '
            'for $userId (expires $expiresAt)',
          );
        }
      } else if (plan == MasterLeaguePlan.pro) {
        await BadgeService.instance.onProSubscriptionPurchased(
          userId: userId,
          expiresAt: expiresAt,
        );
        if (kDebugMode) {
          debugPrint(
            '[MasterLeaguePayment] Pro badge granted '
            'for $userId (expires $expiresAt)',
          );
        }
      }
    } catch (e) {
      // Badge grant must never fail the payment flow.
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] _grantPlanBadges error: $e',
        );
      }
    }
  }

  /// Grants organizer badge after a successful verification purchase.
  Future<void> _grantOrganizerBadge(String userId) async {
    if (userId.trim().isEmpty) return;
    try {
      await BadgeService.instance
          .onOrganizerVerificationPurchased(userId: userId);
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] Organizer badge granted '
          'for $userId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] _grantOrganizerBadge error: $e',
        );
      }
    }
  }

  /// Grants organizer badge renewal after a successful renewal purchase.
  Future<void> _grantOrganizerBadgeRenewal(String userId) async {
    if (userId.trim().isEmpty) return;
    try {
      await BadgeService.instance
          .onOrganizerVerificationRenewalPurchased(
        userId: userId,
      );
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] Organizer badge renewal granted '
          'for $userId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] _grantOrganizerBadgeRenewal '
          'error: $e',
        );
      }
    }
  }

  // ── Google Play Billing paths ─────────────────────────────────────────────

  Future<MasterLeaguePaymentResult> _purchasePlanViaGooglePlay({
    required String userId,
    required MasterLeaguePlan plan,
    required PlanDuration duration,
  }) async {
    final uid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: 'Please sign in to continue.',
      );
    }

    final productId =
        GooglePlayBillingCatalog.subscriptionIdForPlan(
      plan: plan,
      duration: duration,
    );

    if (productId.isEmpty) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage:
            'No Play Store product is configured for '
            '${plan.displayName} ${duration.displayName}.',
      );
    }

    final attemptId =
        await GooglePlayBillingService.instance.createAttempt(
      userId: uid,
      productId: productId,
      productType: 'plan_subscription',
      productSubType: 'plan_${plan.id}_${duration.id}',
      leagueName:
          '${plan.displayName} Plan - ${duration.displayName}',
      planId: plan.id,
      planDurationId: duration.id,
      metadata: <String, dynamic>{
        'plan': plan.id,
        'duration': duration.id,
        'durationMonths': duration.months,
      },
    );

    final gpResult = await GooglePlayBillingService.instance
        .purchasePlanSubscription(
      plan: plan,
      duration: duration,
      userId: uid,
      attemptId: attemptId,
    );

    if (!gpResult.success) {
      final msg = gpResult.errorMessage ?? 'Purchase failed.';
      if (msg.toLowerCase().contains('cancel') &&
          attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
          attemptId: attemptId,
          reason: msg,
        );
      } else if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientFailed(
          attemptId: attemptId,
          errorMessage: msg,
        );
      }
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: msg,
        attemptId: attemptId,
        paymentId: gpResult.paymentId,
      );
    }

    // Grant badges — GooglePlayBillingService._grantBadgesForProduct
    // already handles this via the purchase stream, but we call here
    // as well for immediate consistency via the Flutterwave-equivalent
    // path. The grant is idempotent so double-calling is safe.
    await _grantPlanBadges(
      userId: uid,
      plan: plan,
      duration: duration,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    return MasterLeaguePaymentResult.paid(
      receiptId: gpResult.orderId.isNotEmpty
          ? gpResult.orderId
          : gpResult.purchaseToken,
      paidAtMs: now,
      provider: providerName,
      currency: 'PLAY',
      totalAmount: '',
      attemptId: attemptId,
      paymentId: gpResult.paymentId,
      transactionId: gpResult.orderId,
      txRef: gpResult.purchaseToken,
    );
  }

  Future<MasterLeaguePaymentResult>
      _purchaseVerificationViaGooglePlay({
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  }) async {
    final uid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: 'Please sign in to continue.',
      );
    }

    final attemptId =
        await GooglePlayBillingService.instance.createAttempt(
      userId: uid,
      productId:
          GooglePlayBillingCatalog.organizerVerificationId,
      productType: 'organizer_verification',
      productSubType: 'master_league_organizer_verification',
      leagueName: masterLeagueName,
      metadata: <String, dynamic>{
        'masterLeagueId': masterLeagueId,
        'masterLeagueName': masterLeagueName,
        'verificationMode': 'initial',
      },
    );

    final gpResult = await GooglePlayBillingService.instance
        .purchaseOrganizerVerification(
      userId: uid,
      masterLeagueName: masterLeagueName,
      attemptId: attemptId,
    );

    if (!gpResult.success) {
      final msg = gpResult.errorMessage ?? 'Purchase failed.';
      if (msg.toLowerCase().contains('cancel') &&
          attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
          attemptId: attemptId,
          reason: msg,
        );
      } else if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientFailed(
          attemptId: attemptId,
          errorMessage: msg,
        );
      }
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: msg,
        attemptId: attemptId,
        paymentId: gpResult.paymentId,
      );
    }

    // Grant organizer badge (Google Play stream also does this,
    // but we call explicitly for immediate UI consistency).
    await _grantOrganizerBadge(uid);

    final now = DateTime.now().millisecondsSinceEpoch;
    return MasterLeaguePaymentResult.paid(
      receiptId: gpResult.orderId.isNotEmpty
          ? gpResult.orderId
          : gpResult.purchaseToken,
      paidAtMs: now,
      provider: providerName,
      currency: 'PLAY',
      totalAmount: '',
      attemptId: attemptId,
      paymentId: gpResult.paymentId,
      transactionId: gpResult.orderId,
      txRef: gpResult.purchaseToken,
    );
  }

  Future<MasterLeaguePaymentResult>
      _purchaseVerificationRenewalViaGooglePlay({
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  }) async {
    final uid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: 'Please sign in to continue.',
      );
    }

    final attemptId =
        await GooglePlayBillingService.instance.createAttempt(
      userId: uid,
      productId:
          GooglePlayBillingCatalog.organizerVerificationRenewalId,
      productType: 'organizer_verification_renewal',
      productSubType:
          'master_league_organizer_verification_renewal',
      leagueName: masterLeagueName,
      metadata: <String, dynamic>{
        'masterLeagueId': masterLeagueId,
        'masterLeagueName': masterLeagueName,
        'verificationMode': 'renewal',
      },
    );

    final gpResult = await GooglePlayBillingService.instance
        .purchaseOrganizerVerificationRenewal(
      userId: uid,
      masterLeagueName: masterLeagueName,
      attemptId: attemptId,
    );

    if (!gpResult.success) {
      final msg = gpResult.errorMessage ?? 'Purchase failed.';
      if (msg.toLowerCase().contains('cancel') &&
          attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
          attemptId: attemptId,
          reason: msg,
        );
      } else if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientFailed(
          attemptId: attemptId,
          errorMessage: msg,
        );
      }
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: msg,
        attemptId: attemptId,
        paymentId: gpResult.paymentId,
      );
    }

    await _grantOrganizerBadgeRenewal(uid);

    final now = DateTime.now().millisecondsSinceEpoch;
    return MasterLeaguePaymentResult.paid(
      receiptId: gpResult.orderId.isNotEmpty
          ? gpResult.orderId
          : gpResult.purchaseToken,
      paidAtMs: now,
      provider: providerName,
      currency: 'PLAY',
      totalAmount: '',
      attemptId: attemptId,
      paymentId: gpResult.paymentId,
      transactionId: gpResult.orderId,
      txRef: gpResult.purchaseToken,
    );
  }

  // ── Flutterwave path ──────────────────────────────────────────────────────

  Future<MasterLeaguePaymentResult> _runFlutterwavePayment({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,
    required String productType,
    required String productSubType,
    required Map<String, dynamic> metadata,
    required List<PaymentLineItem> items,
    required String txRefPrefix,
    required String description,
    required double amount,
    required String currency,
    required String analyticsKind,
    String planId = '',
    String planDurationId = '',
    // Badge grant callbacks invoked on verified success.
    Future<void> Function(String uid)? onSuccessBadgeGrant,
  }) async {
    String attemptId = '';
    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please sign in to continue.',
        );
      }

      final authUid = currentUser.uid.trim();
      if (authUid.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please sign in to continue.',
        );
      }

      FlutterwaveConfig.assertConfigured();

      final rounded = _roundMoney(currency, amount);
      if (rounded <= 0) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Payment amount is invalid.',
          currency: currency,
        );
      }

      final totalAmount = _toFlutterwaveAmount(rounded);
      final safeLeagueName = leagueName.trim();

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: providerName,
          currency: currency,
          amount: rounded,
          amountStr: totalAmount,
          userId: authUid,
          leagueId: leagueId,
          leagueName: safeLeagueName,
          masterLeagueId: leagueId,
          productType: productType,
          productSubType: productSubType,
          planId: planId,
          planDurationId: planDurationId,
          metadata: metadata,
          items: items,
        ),
      );

      if (attemptId.trim().isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Unable to start payment. Please try again.',
          currency: currency,
          totalAmount: totalAmount,
        );
      }

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: analyticsKind,
        leagueId: leagueId,
        leagueName: safeLeagueName,
        provider: providerName,
        currency: currency,
        amount: totalAmount,
        userId: effectiveUserId,
      );

      final String email =
          (currentUser.email?.trim().isNotEmpty ?? false)
              ? currentUser.email!.trim()
              : 'user_$effectiveUserId@eleaguehub.app';
      final String phone =
          (currentUser.phoneNumber?.trim().isNotEmpty ?? false)
              ? currentUser.phoneNumber!.trim()
              : '0000000000';
      final String name =
          (currentUser.displayName?.trim().isNotEmpty ?? false)
              ? currentUser.displayName!.trim()
              : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final txRef =
          '$txRefPrefix-${DateTime.now().millisecondsSinceEpoch}'
          '-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: _paymentOptionsForCurrency(currency),
        customization: Customization(
          title: 'EleagueHub',
          description: description,
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response =
          await flutterwave.charge(context);

      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] charge result: '
          'success=${response.success} '
          'status=${response.status} '
          'txRef=${response.txRef} '
          'transactionId=${response.transactionId}',
        );
      }

      if (_isChargeSuccessful(response)) {
        final txId =
            (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          await PaymentsService.instance.markClientFailed(
            attemptId: attemptId,
            errorMessage: 'Missing transactionId.',
          );
          return MasterLeaguePaymentResult.failed(
            provider: providerName,
            errorMessage:
                'Payment success returned without transaction id.',
            currency: currency,
            totalAmount: totalAmount,
            attemptId: attemptId,
          );
        }

        final resolvedTxRef =
            (response.txRef?.toString().trim().isNotEmpty ?? false)
                ? response.txRef!.toString().trim()
                : txRef;

        final verification =
            await PaymentsService.instance.verifyFlutterwavePayment(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        if (!verification.success) {
          final cleanError = _cleanErrorMessage(
            verification.errorMessage ??
                'Payment verification failed.',
          );

          await AppAnalyticsService.instance.logPaymentResult(
            kind: analyticsKind,
            leagueId: leagueId,
            leagueName: safeLeagueName,
            success: false,
            provider: providerName,
            currency: currency,
            amount: totalAmount,
            receiptId: null,
            errorMessage: cleanError,
            userId: effectiveUserId,
          );

          return MasterLeaguePaymentResult.failed(
            provider: providerName,
            errorMessage: cleanError,
            currency: currency,
            totalAmount: totalAmount,
            attemptId: attemptId,
            paymentId: verification.paymentId,
            transactionId: txId,
            txRef: resolvedTxRef,
          );
        }

        // ── Grant badges after verified payment ───────────────────────
        if (onSuccessBadgeGrant != null) {
          await onSuccessBadgeGrant(authUid);
        }
        // ─────────────────────────────────────────────────────────────

        await AppAnalyticsService.instance.logPaymentResult(
          kind: analyticsKind,
          leagueId: leagueId,
          leagueName: safeLeagueName,
          success: true,
          provider: providerName,
          currency: verification.currency.isNotEmpty
              ? verification.currency
              : currency,
          amount: verification.amountStr.isNotEmpty
              ? verification.amountStr
              : totalAmount,
          receiptId: verification.receiptId,
          errorMessage: null,
          userId: effectiveUserId,
        );

        return MasterLeaguePaymentResult.paid(
          receiptId: verification.receiptId,
          paidAtMs: verification.paidAtMs,
          provider: verification.provider,
          currency: verification.currency.isNotEmpty
              ? verification.currency
              : currency,
          totalAmount: verification.amountStr.isNotEmpty
              ? verification.amountStr
              : totalAmount,
          attemptId: attemptId,
          paymentId: verification.paymentId,
          transactionId: verification.transactionId,
          txRef: verification.txRef,
        );
      }

      final status =
          (response.status ?? '').toString().trim().toLowerCase();
      final msg = status == 'cancelled' || status == 'cancel'
          ? 'Payment was cancelled.'
          : status.isNotEmpty
              ? 'Payment not successful (status: $status).'
              : 'Payment cancelled or not successful.';

      await PaymentsService.instance.markClientCancelled(
        attemptId: attemptId,
        reason: msg,
      );

      await AppAnalyticsService.instance.logPaymentResult(
        kind: analyticsKind,
        leagueId: leagueId,
        leagueName: safeLeagueName,
        success: false,
        provider: providerName,
        currency: currency,
        amount: totalAmount,
        receiptId: null,
        errorMessage: msg,
        userId: effectiveUserId,
      );

      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: msg,
        currency: currency,
        totalAmount: totalAmount,
        attemptId: attemptId,
      );
    } catch (e) {
      final cleanError = _cleanErrorMessage(e);

      if (attemptId.isNotEmpty) {
        try {
          await PaymentsService.instance.markClientFailed(
            attemptId: attemptId,
            errorMessage: cleanError,
          );
        } catch (_) {}
      }

      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: cleanError,
        currency: currency,
        attemptId: attemptId,
      );
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  @override
  Future<MasterLeaguePaymentResult> payForPlanSubscription({
    required BuildContext context,
    required String userId,
    required MasterLeaguePlan plan,
    required PlanDuration duration,
  }) async {
    // ── Android → Google Play Billing ─────────────────────────────────────
    if (PaymentPlatformConfig
        .routeAndroidPaymentsToGooglePlayBilling) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] payForPlanSubscription '
          '→ Google Play Billing',
        );
      }
      return _purchasePlanViaGooglePlay(
        userId: userId,
        plan: plan,
        duration: duration,
      );
    }

    // ── Web / other → Flutterwave ─────────────────────────────────────────
    if (kDebugMode) {
      debugPrint(
        '[MasterLeaguePayment] payForPlanSubscription '
        '→ Flutterwave',
      );
    }

    try {
      final remotePlan =
          await RemotePricingService.instance.getPlanForLocale(
        _effectiveLocale(context),
      );

      if (!remotePlan.paymentsEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!remotePlan.flutterwaveEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Flutterwave payments are currently unavailable.',
        );
      }

      final pricing = MasterLeaguePricingService();
      final price = await pricing.getPlanPrice(
        plan: plan,
        duration: duration,
        locale: _effectiveLocale(context),
      );

      if (price == null) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              "${plan.displayName} ${duration.displayName} price "
              "isn't configured yet. Please try again later.",
        );
      }

      final currencyUsed = price.currency.trim().toUpperCase();

      return _runFlutterwavePayment(
        context: context,
        userId: userId,
        leagueId: '',
        leagueName:
            '${plan.displayName} Plan - ${duration.displayName}',
        productType: 'plan_subscription',
        productSubType: 'plan_${plan.id}_${duration.id}',
        planId: plan.id,
        planDurationId: duration.id,
        metadata: <String, dynamic>{
          'plan': plan.id,
          'duration': duration.id,
          'durationMonths': duration.months,
        },
        items: <PaymentLineItem>[
          PaymentLineItem(
            productType: 'plan_subscription',
            productSubType: 'plan_${plan.id}_${duration.id}',
            quantity: 1,
            amount: price.amount,
          ),
        ],
        txRefPrefix:
            'EH-PLAN-${plan.id.toUpperCase()}'
            '-${duration.id.toUpperCase()}',
        description:
            '${plan.displayName} Plan (${duration.displayName}) '
            'subscription',
        amount: price.amount,
        currency: currencyUsed,
        analyticsKind: 'plan_subscription',
        // Badge grant callback for Flutterwave path.
        onSuccessBadgeGrant: (String uid) => _grantPlanBadges(
          userId: uid,
          plan: plan,
          duration: duration,
        ),
      );
    } catch (e) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
      );
    }
  }

  @override
  Future<MasterLeaguePaymentResult> payForOrganizerVerification({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  }) async {
    // ── Android → Google Play Billing ─────────────────────────────────────
    if (PaymentPlatformConfig
        .routeAndroidPaymentsToGooglePlayBilling) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] payForOrganizerVerification '
          '→ Google Play Billing',
        );
      }
      return _purchaseVerificationViaGooglePlay(
        userId: userId,
        masterLeagueId: masterLeagueId,
        masterLeagueName: masterLeagueName,
      );
    }

    // ── Web / other → Flutterwave ─────────────────────────────────────────
    if (kDebugMode) {
      debugPrint(
        '[MasterLeaguePayment] payForOrganizerVerification '
        '→ Flutterwave',
      );
    }

    try {
      final safeMasterLeagueId = masterLeagueId.trim();
      final safeMasterLeagueName = masterLeagueName.trim();

      if (safeMasterLeagueId.isEmpty ||
          safeMasterLeagueName.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Master League information is missing.',
        );
      }

      final remotePlan =
          await RemotePricingService.instance.getPlanForLocale(
        _effectiveLocale(context),
      );

      if (!remotePlan.paymentsEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!remotePlan.flutterwaveEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Flutterwave payments are currently unavailable.',
        );
      }

      if (!remotePlan.organizerVerificationEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Organizer verification is currently disabled.',
        );
      }

      final fee = remotePlan.organizerVerificationFee;
      if (fee <= 0) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Organizer verification price is not configured '
              'correctly.',
        );
      }

      final currencyUsed =
          remotePlan.currency.trim().toUpperCase();

      return _runFlutterwavePayment(
        context: context,
        userId: userId,
        leagueId: safeMasterLeagueId,
        leagueName: safeMasterLeagueName,
        productType: 'organizer_verification',
        productSubType: 'master_league_organizer_verification',
        metadata: <String, dynamic>{
          'masterLeagueId': safeMasterLeagueId,
          'masterLeagueName': safeMasterLeagueName,
          'verificationMode': 'initial',
        },
        items: <PaymentLineItem>[
          PaymentLineItem(
            productType: 'organizer_verification',
            productSubType:
                'master_league_organizer_verification',
            quantity: 1,
            amount: fee,
          ),
        ],
        txRefPrefix: 'EH-ORGV',
        description:
            'Organizer verification: $safeMasterLeagueName',
        amount: fee,
        currency: currencyUsed,
        analyticsKind: 'organizer_verification',
        // Grant organizer badge on Flutterwave success.
        onSuccessBadgeGrant: (String uid) =>
            _grantOrganizerBadge(uid),
      );
    } catch (e) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
      );
    }
  }

  @override
  Future<MasterLeaguePaymentResult>
      payForOrganizerVerificationRenewal({
    required BuildContext context,
    required String userId,
    required String masterLeagueId,
    required String masterLeagueName,
  }) async {
    // ── Android → Google Play Billing ─────────────────────────────────────
    if (PaymentPlatformConfig
        .routeAndroidPaymentsToGooglePlayBilling) {
      if (kDebugMode) {
        debugPrint(
          '[MasterLeaguePayment] payForOrganizerVerificationRenewal '
          '→ Google Play Billing',
        );
      }
      return _purchaseVerificationRenewalViaGooglePlay(
        userId: userId,
        masterLeagueId: masterLeagueId,
        masterLeagueName: masterLeagueName,
      );
    }

    // ── Web / other → Flutterwave ─────────────────────────────────────────
    if (kDebugMode) {
      debugPrint(
        '[MasterLeaguePayment] payForOrganizerVerificationRenewal '
        '→ Flutterwave',
      );
    }

    try {
      final safeMasterLeagueId = masterLeagueId.trim();
      final safeMasterLeagueName = masterLeagueName.trim();

      if (safeMasterLeagueId.isEmpty ||
          safeMasterLeagueName.isEmpty) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage: 'Master League information is missing.',
        );
      }

      final remotePlan =
          await RemotePricingService.instance.getPlanForLocale(
        _effectiveLocale(context),
      );

      if (!remotePlan.paymentsEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
        );
      }

      if (!remotePlan.flutterwaveEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Flutterwave payments are currently unavailable.',
        );
      }

      if (!remotePlan.organizerVerificationRenewalEnabled) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Verification renewal is currently disabled.',
        );
      }

      final fee = remotePlan.organizerVerificationRenewalFee;
      if (fee <= 0) {
        return MasterLeaguePaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Verification renewal price is not configured '
              'correctly.',
        );
      }

      final currencyUsed =
          remotePlan.currency.trim().toUpperCase();

      return _runFlutterwavePayment(
        context: context,
        userId: userId,
        leagueId: safeMasterLeagueId,
        leagueName: safeMasterLeagueName,
        productType: 'organizer_verification_renewal',
        productSubType:
            'master_league_organizer_verification_renewal',
        metadata: <String, dynamic>{
          'masterLeagueId': safeMasterLeagueId,
          'masterLeagueName': safeMasterLeagueName,
          'verificationMode': 'renewal',
          'verificationDurationDays':
              remotePlan.organizerVerificationDurationDays,
        },
        items: <PaymentLineItem>[
          PaymentLineItem(
            productType: 'organizer_verification_renewal',
            productSubType:
                'master_league_organizer_verification_renewal',
            quantity: 1,
            amount: fee,
          ),
        ],
        txRefPrefix: 'EH-ORGR',
        description:
            'Verification renewal: $safeMasterLeagueName',
        amount: fee,
        currency: currencyUsed,
        analyticsKind: 'organizer_verification_renewal',
        // Grant renewal badge on Flutterwave success.
        onSuccessBadgeGrant: (String uid) =>
            _grantOrganizerBadgeRenewal(uid),
      );
    } catch (e) {
      return MasterLeaguePaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
      );
    }
  }
}