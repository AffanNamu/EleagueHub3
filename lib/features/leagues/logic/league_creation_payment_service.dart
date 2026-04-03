import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/payments/payment_models.dart';
import '../../../core/services/payments/payments_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../master_leagues/domain/master_league_plan.dart';
import '../../master_leagues/logic/master_league_pricing_service.dart';

final leagueCreationPaymentServiceProvider =
    Provider<LeagueCreationPaymentService>((ref) {
  return FlutterwaveLeagueCreationPaymentService();
});

class LeagueCreationPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;
  final int viewerCapacity;
  final bool buyCouponsForParticipants;
  final int couponDiscountPercent;
  final int couponCount;
  final String totalAmount;
  final String selectedPlanId;
  final String attemptId;
  final String paymentId;
  final String transactionId;
  final String txRef;

  const LeagueCreationPaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.viewerCapacity,
    required this.buyCouponsForParticipants,
    required this.couponDiscountPercent,
    required this.couponCount,
    required this.totalAmount,
    required this.selectedPlanId,
    required this.attemptId,
    required this.paymentId,
    required this.transactionId,
    required this.txRef,
  });

  factory LeagueCreationPaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required int viewerCapacity,
    required bool buyCouponsForParticipants,
    required int couponDiscountPercent,
    required int couponCount,
    required String totalAmount,
    String selectedPlanId = '',
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) {
    return LeagueCreationPaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
      viewerCapacity: viewerCapacity,
      buyCouponsForParticipants: buyCouponsForParticipants,
      couponDiscountPercent: couponDiscountPercent.clamp(0, 100),
      couponCount: couponCount,
      totalAmount: totalAmount,
      selectedPlanId: selectedPlanId,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }

  factory LeagueCreationPaymentResult.failed({
    required String provider,
    required String errorMessage,
    int viewerCapacity = 0,
    bool buyCouponsForParticipants = false,
    int couponDiscountPercent = 0,
    int couponCount = 0,
    String totalAmount = '0',
    String selectedPlanId = '',
    String attemptId = '',
    String paymentId = '',
    String transactionId = '',
    String txRef = '',
  }) {
    return LeagueCreationPaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
      viewerCapacity: viewerCapacity,
      buyCouponsForParticipants: buyCouponsForParticipants,
      couponDiscountPercent: couponDiscountPercent.clamp(0, 100),
      couponCount: couponCount,
      totalAmount: totalAmount,
      selectedPlanId: selectedPlanId,
      attemptId: attemptId,
      paymentId: paymentId,
      transactionId: transactionId,
      txRef: txRef,
    );
  }
}

abstract class LeagueCreationPaymentService {
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
    bool addonsOnly,
    bool premiumUpgrade,
    MasterLeaguePlan? selectedPlan,
    int viewerCapacity,
    bool buyCouponsForParticipants,
    int couponDiscountPercent,
    int couponCount,
  });

  String get providerName;
}

class FlutterwaveLeagueCreationPaymentService
    implements LeagueCreationPaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  int _sanitizeCount(int v) => v < 0 ? 0 : v;
  int _sanitizePercent(int v) => v.clamp(0, 100);

  double _roundMoney(String currency, double v) {
    final c = currency.trim().toUpperCase();
    if (c == 'NGN') return v.roundToDouble();
    return double.parse(v.toStringAsFixed(2));
  }

  bool _isChargeSuccessful(ChargeResponse response) {
    final status = (response.status ?? '').toString().trim().toLowerCase();
    return response.success == true || status == 'successful';
  }

  String _cleanErrorMessage(Object error) {
    final raw = error.toString().trim();

    if (raw.contains('Payment verification endpoint was not found (404)')) {
      return 'Payment verification service is not available right now. Please contact support or try again later.';
    }
    if (raw.contains('Payment verification failed (404)')) {
      return 'Payment verification service is not available right now. Please contact support or try again later.';
    }
    if (raw.contains('Bad state:')) {
      return raw.replaceFirst('Bad state:', '').trim();
    }
    if (raw.contains('SocketException')) {
      return 'Network error while verifying payment. Please check your internet and try again.';
    }
    if (raw.contains('timed out')) {
      return 'Payment verification timed out. Please try again.';
    }
    return raw;
  }

  @override
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
    bool addonsOnly = false,
    bool premiumUpgrade = false,
    MasterLeaguePlan? selectedPlan,
    int viewerCapacity = 0,
    bool buyCouponsForParticipants = false,
    int couponDiscountPercent = 0,
    int couponCount = 0,
  }) async {
    final discountPercent = _sanitizePercent(couponDiscountPercent);
    final safeCouponCount =
        buyCouponsForParticipants ? _sanitizeCount(couponCount) : 0;
    final chosenPlan = selectedPlan ?? MasterLeaguePlan.pro;

    String attemptId = '';
    String totalAmount = '';
    String currencyUsed = '';

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.uid.trim().isEmpty) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please sign in to continue.',
          selectedPlanId: chosenPlan.id,
        );
      }

      final safeLeagueName = leagueName.trim();
      if (safeLeagueName.isEmpty) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage: 'League name is required.',
          selectedPlanId: chosenPlan.id,
        );
      }

      final plan = await RemotePricingService.instance.getPlanForLocale(
        Localizations.maybeLocaleOf(context),
      );

      if (!plan.paymentsEnabled) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Payments are temporarily disabled by the administrator.',
          selectedPlanId: chosenPlan.id,
        );
      }

      if (!plan.flutterwaveEnabled) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Flutterwave payments are currently unavailable.',
          selectedPlanId: chosenPlan.id,
        );
      }

      double base = 0.0;
      String productType = '';
      String productSubType = '';

      if (premiumUpgrade) {
        final mlPrice = await MasterLeaguePricingService().getPlanPrice(
          plan: chosenPlan,
          duration: PlanDuration.threeMonths,
          locale: Localizations.maybeLocaleOf(context),
        );

        if (mlPrice == null) {
          return LeagueCreationPaymentResult.failed(
            provider: providerName,
            errorMessage:
                "${chosenPlan.displayName} price isn't configured yet. Please try again later.",
            selectedPlanId: chosenPlan.id,
          );
        }

        currencyUsed = mlPrice.currency.trim().toUpperCase();
        base = mlPrice.amount.toDouble();
        productType = 'plan_subscription';
        productSubType = 'plan_${chosenPlan.id}_3mo';
      } else {
        currencyUsed = plan.currency.trim().toUpperCase();
        base = addonsOnly ? 0.0 : plan.createLeagueFee;
        productType = addonsOnly ? 'league_upgrade' : 'league_creation';
        productSubType =
            addonsOnly ? 'league_addons_only' : 'league_creation_checkout';
      }

      if (currencyUsed.isEmpty) {
        currencyUsed = plan.currency.trim().toUpperCase();
      }

      if (!premiumUpgrade &&
          buyCouponsForParticipants &&
          safeCouponCount > 0 &&
          discountPercent <= 0) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Discount must be greater than 0 when buying coupons.',
          selectedPlanId: chosenPlan.id,
        );
      }

      final couponPricing =
          RemotePricingService.instance.computeOrganizerCouponPricing(
        plan: plan,
        couponCount: premiumUpgrade ? 0 : safeCouponCount,
        discountPercent: premiumUpgrade ? 0 : discountPercent,
      );

      final totalNumeric = _roundMoney(
        currencyUsed,
        base + (premiumUpgrade ? 0.0 : couponPricing.discountedSubtotal),
      );

      if (totalNumeric <= 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        return LeagueCreationPaymentResult.paid(
          receiptId: 'FREE-$now',
          paidAtMs: now,
          provider: 'free',
          viewerCapacity: 0,
          buyCouponsForParticipants: false,
          couponDiscountPercent: 0,
          couponCount: 0,
          totalAmount: '0',
          selectedPlanId: chosenPlan.id,
        );
      }

      FlutterwaveConfig.assertConfigured();
      totalAmount = _toFlutterwaveAmount(totalNumeric);

      final items = <PaymentLineItem>[
        if (premiumUpgrade)
          PaymentLineItem(
            productType: 'plan_subscription',
            productSubType: productSubType,
            quantity: 1,
            amount: base,
          ),
        if (!premiumUpgrade && !addonsOnly)
          PaymentLineItem(
            productType: 'league_creation',
            productSubType: 'league_creation_base',
            quantity: 1,
            amount: base,
          ),
        if (!premiumUpgrade && safeCouponCount > 0)
          PaymentLineItem(
            productType: 'coupon_pack',
            productSubType: 'coupon_pack_purchase',
            quantity: safeCouponCount,
            amount: couponPricing.discountedSubtotal,
          ),
      ];

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: providerName,
          currency: currencyUsed,
          amount: totalNumeric,
          amountStr: totalAmount,
          userId: authUser.uid,
          leagueId: '',
          leagueName: safeLeagueName,
          productType: productType,
          productSubType: productSubType,
          planId: premiumUpgrade ? chosenPlan.id : '',
          planDurationId: premiumUpgrade ? '3mo' : '',
          metadata: <String, dynamic>{
            'addonsOnly': addonsOnly,
            'premiumUpgrade': premiumUpgrade,
            'selectedPlanId': chosenPlan.id,
            'viewerCapacity': viewerCapacity,
            'buyCouponsForParticipants':
                premiumUpgrade ? false : buyCouponsForParticipants,
            'couponDiscountPercent': premiumUpgrade ? 0 : discountPercent,
            'couponCount': premiumUpgrade ? 0 : safeCouponCount,
          },
          items: items,
        ),
      );

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: premiumUpgrade
            ? 'plan_subscription'
            : (addonsOnly ? 'league_upgrade' : 'league_creation'),
        leagueId: '',
        leagueName: safeLeagueName,
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        userId: userId,
      );

      final String email = (authUser.email?.trim().isNotEmpty ?? false)
          ? authUser.email!.trim()
          : 'user_$userId@eleaguehub.app';
      final String phone = (authUser.phoneNumber?.trim().isNotEmpty ?? false)
          ? authUser.phoneNumber!.trim()
          : '0000000000';
      final String name = (authUser.displayName?.trim().isNotEmpty ?? false)
          ? authUser.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final txRef = premiumUpgrade
          ? 'EH-PLAN-${chosenPlan.id.toUpperCase()}-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}'
          : (addonsOnly
              ? 'EH-UPG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}'
              : 'EH-CRT-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}');

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currencyUsed,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions:
            currencyUsed == 'NGN' ? 'card,ussd,banktransfer' : 'card',
        customization: Customization(
          title: 'EleagueHub',
          description: premiumUpgrade
              ? 'Plan purchase: ${chosenPlan.displayName}'
              : (addonsOnly
                  ? 'League upgrade: $safeLeagueName'
                  : 'League creation: $safeLeagueName'),
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (_isChargeSuccessful(response)) {
        final txId = (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          if (attemptId.isNotEmpty) {
            await PaymentsService.instance.markClientFailed(
              attemptId: attemptId,
              errorMessage: 'Missing transactionId.',
            );
          }
          return LeagueCreationPaymentResult.failed(
            provider: providerName,
            errorMessage: 'Missing transaction id.',
            totalAmount: totalAmount,
            buyCouponsForParticipants: false,
            couponDiscountPercent: 0,
            couponCount: 0,
            selectedPlanId: chosenPlan.id,
            attemptId: attemptId,
          );
        }

        final resolvedTxRef =
            (response.txRef?.trim().isNotEmpty ?? false)
                ? response.txRef!.trim()
                : txRef;

        final verification =
            await PaymentsService.instance.verifyFlutterwavePayment(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        if (!verification.success) {
          final cleanError = _cleanErrorMessage(
            verification.errorMessage ?? 'Payment verification failed.',
          );

          await AppAnalyticsService.instance.logPaymentResult(
            kind: premiumUpgrade
                ? 'plan_subscription'
                : (addonsOnly ? 'league_upgrade' : 'league_creation'),
            leagueId: '',
            leagueName: safeLeagueName,
            success: false,
            provider: providerName,
            currency: currencyUsed,
            amount: totalAmount,
            receiptId: null,
            errorMessage: cleanError,
            userId: userId,
          );

          return LeagueCreationPaymentResult.failed(
            provider: providerName,
            errorMessage: cleanError,
            totalAmount: totalAmount,
            selectedPlanId: chosenPlan.id,
            attemptId: attemptId,
            paymentId: verification.paymentId,
            transactionId: txId,
            txRef: resolvedTxRef,
          );
        }

        await AppAnalyticsService.instance.logPaymentResult(
          kind: premiumUpgrade
              ? 'plan_subscription'
              : (addonsOnly ? 'league_upgrade' : 'league_creation'),
          leagueId: '',
          leagueName: safeLeagueName,
          success: true,
          provider: providerName,
          currency: verification.currency.isNotEmpty
              ? verification.currency
              : currencyUsed,
          amount: verification.amountStr.isNotEmpty
              ? verification.amountStr
              : totalAmount,
          receiptId: verification.receiptId,
          errorMessage: null,
          userId: userId,
        );

        return LeagueCreationPaymentResult.paid(
          receiptId: verification.receiptId,
          paidAtMs: verification.paidAtMs,
          provider: verification.provider,
          viewerCapacity: 0,
          buyCouponsForParticipants:
              premiumUpgrade ? false : buyCouponsForParticipants,
          couponDiscountPercent: premiumUpgrade ? 0 : discountPercent,
          couponCount: premiumUpgrade ? 0 : safeCouponCount,
          totalAmount: verification.amountStr.isNotEmpty
              ? verification.amountStr
              : totalAmount,
          selectedPlanId: chosenPlan.id,
          attemptId: attemptId,
          paymentId: verification.paymentId,
          transactionId: verification.transactionId,
          txRef: verification.txRef,
        );
      }

      if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(
          attemptId: attemptId,
          reason: 'Payment cancelled or not successful',
        );
      }

      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        viewerCapacity: 0,
        buyCouponsForParticipants:
            premiumUpgrade ? false : buyCouponsForParticipants,
        couponDiscountPercent: premiumUpgrade ? 0 : discountPercent,
        couponCount: premiumUpgrade ? 0 : safeCouponCount,
        totalAmount: totalAmount,
        selectedPlanId: chosenPlan.id,
        attemptId: attemptId,
      );
    } catch (e) {
      if (attemptId.isNotEmpty) {
        try {
          await PaymentsService.instance.markClientFailed(
            attemptId: attemptId,
            errorMessage: e.toString(),
          );
        } catch (_) {}
      }

      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: _cleanErrorMessage(e),
        viewerCapacity: 0,
        buyCouponsForParticipants:
            premiumUpgrade ? false : buyCouponsForParticipants,
        couponDiscountPercent: premiumUpgrade ? 0 : discountPercent,
        couponCount: premiumUpgrade ? 0 : safeCouponCount,
        totalAmount: totalAmount,
        selectedPlanId: chosenPlan.id,
        attemptId: attemptId,
      );
    }
  }
}
