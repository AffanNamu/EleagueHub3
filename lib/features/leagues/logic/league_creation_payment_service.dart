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
    );
  }
}

abstract class LeagueCreationPaymentService {
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
    bool addonsOnly,
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

  @override
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
    bool addonsOnly = false,
    int viewerCapacity = 0,
    bool buyCouponsForParticipants = false,
    int couponDiscountPercent = 0,
    int couponCount = 0,
  }) async {
    final discountPercent = _sanitizePercent(couponDiscountPercent);
    final safeCouponCount = buyCouponsForParticipants ? _sanitizeCount(couponCount) : 0;

    String attemptId = '';
    String totalAmount = '0';

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.uid.trim().isEmpty) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Please sign in to continue.',
        );
      }

      final safeLeagueName = leagueName.trim();
      if (safeLeagueName.isEmpty) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage: 'League name is required.',
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
        );
      }

      if (!plan.flutterwaveEnabled) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage:
              'Flutterwave payments are currently unavailable.',
        );
      }

      final base = addonsOnly ? 0.0 : plan.createLeagueFee;

      if (buyCouponsForParticipants && safeCouponCount > 0 && discountPercent <= 0) {
        return LeagueCreationPaymentResult.failed(
          provider: providerName,
          errorMessage: 'Discount must be greater than 0 when buying coupons.',
        );
      }

      final couponPricing =
          RemotePricingService.instance.computeOrganizerCouponPricing(
        plan: plan,
        couponCount: safeCouponCount,
        discountPercent: discountPercent,
      );

      final totalNumeric =
          _roundMoney(plan.currency, base + couponPricing.discountedSubtotal);

      if (totalNumeric <= 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        return LeagueCreationPaymentResult.paid(
          receiptId: 'FREE-$now',
          paidAtMs: now,
          provider: 'free',
          viewerCapacity: 0,
          buyCouponsForParticipants: buyCouponsForParticipants,
          couponDiscountPercent: discountPercent,
          couponCount: safeCouponCount,
          totalAmount: '0',
        );
      }

      FlutterwaveConfig.assertConfigured();
      totalAmount = _toFlutterwaveAmount(totalNumeric);

      final items = <PaymentLineItem>[
        if (!addonsOnly)
          PaymentLineItem(
            productType: 'league_creation',
            productSubType: 'league_creation_base',
            quantity: 1,
            amount: base,
          ),
        if (safeCouponCount > 0)
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
          currency: plan.currency,
          amount: totalNumeric,
          amountStr: totalAmount,
          userId: authUser.uid,
          leagueId: '',
          leagueName: safeLeagueName,
          productType: addonsOnly ? 'league_upgrade' : 'league_creation',
          productSubType:
              addonsOnly ? 'league_addons_only' : 'league_creation_checkout',
          metadata: <String, dynamic>{
            'addonsOnly': addonsOnly,
            'viewerCapacity': viewerCapacity,
            'buyCouponsForParticipants': buyCouponsForParticipants,
            'couponDiscountPercent': discountPercent,
            'couponCount': safeCouponCount,
          },
          items: items,
        ),
      );

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: addonsOnly ? 'league_upgrade' : 'league_creation',
        leagueId: '',
        leagueName: safeLeagueName,
        provider: providerName,
        currency: plan.currency,
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

      final customer = Customer(name: name, phoneNumber: phone, email: email);

      final txRef = addonsOnly
          ? 'EH-UPG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}'
          : 'EH-CRT-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: plan.currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: plan.currency.toUpperCase() == 'NGN'
            ? 'card,ussd,banktransfer'
            : 'card',
        customization: Customization(
          title: 'EleagueHub',
          description: addonsOnly
              ? 'League upgrade: $safeLeagueName'
              : 'League creation: $safeLeagueName',
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
            buyCouponsForParticipants: buyCouponsForParticipants,
            couponDiscountPercent: discountPercent,
            couponCount: safeCouponCount,
          );
        }

        final resolvedTxRef =
            (response.txRef?.trim().isNotEmpty ?? false)
                ? response.txRef!.trim()
                : txRef;

        final recorded =
            await PaymentsService.instance.recordFlutterwaveClientSuccess(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        return LeagueCreationPaymentResult.paid(
          receiptId: recorded.receiptId,
          paidAtMs: recorded.paidAtMs,
          provider: providerName,
          viewerCapacity: 0,
          buyCouponsForParticipants: buyCouponsForParticipants,
          couponDiscountPercent: discountPercent,
          couponCount: safeCouponCount,
          totalAmount: totalAmount,
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
        buyCouponsForParticipants: buyCouponsForParticipants,
        couponDiscountPercent: discountPercent,
        couponCount: safeCouponCount,
        totalAmount: totalAmount,
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
        errorMessage: e.toString(),
        viewerCapacity: 0,
        buyCouponsForParticipants: buyCouponsForParticipants,
        couponDiscountPercent: discountPercent,
        couponCount: safeCouponCount,
        totalAmount: totalAmount,
      );
    }
  }
}
