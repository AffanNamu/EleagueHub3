import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/services/app_analytics_service.dart';

final leagueCreationPaymentServiceProvider = Provider<LeagueCreationPaymentService>((ref) {
  return FlutterwaveLeagueCreationPaymentService();
});

class LeagueCreationPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

  // LEGACY FIELDS (kept for backward compatibility in callers):
  final int viewerCapacity;

  final bool buyCouponsForParticipants;

  // DISCOUNT percent (0..100) for users at redemption time.
  final int couponDiscountPercent;

  // Coupons to buy (creation) / additional coupons (upgrade).
  final int couponCount;

  // Amount charged (Flutterwave string format).
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
    int viewerCapacity, // deprecated/ignored
    bool buyCouponsForParticipants,
    int couponDiscountPercent,
    int couponCount,
  });

  String get providerName;
}

class FlutterwaveLeagueCreationPaymentService implements LeagueCreationPaymentService {
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

  @override
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
    bool addonsOnly = false,
    int viewerCapacity = 0, // ignored
    bool buyCouponsForParticipants = false,
    int couponDiscountPercent = 0,
    int couponCount = 0,
  }) async {
    final discountPercent = _sanitizePercent(couponDiscountPercent);
    final safeCouponCount = buyCouponsForParticipants ? _sanitizeCount(couponCount) : 0;

    try {
      final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));

      final base = addonsOnly ? 0.0 : plan.createLeagueFee;

      // If buying coupons (>0), discount must be > 0 (prevents 0-cost purchases + keeps couponConfig unitPrice > 0).
      if (buyCouponsForParticipants && safeCouponCount > 0 && discountPercent <= 0) {
        throw StateError('Discount must be > 0 when buying coupons.');
      }

      final couponPricing = RemotePricingService.instance.computeOrganizerCouponPricing(
        plan: plan,
        couponCount: safeCouponCount,
        discountPercent: discountPercent,
      );

      final total = _roundMoney(plan.currency, base + couponPricing.discountedSubtotal);

      // If total is 0 (addonsOnly + couponCount=0), return free success for discount-only adjustments.
      if (total <= 0) {
        final now = DateTime.now().millisecondsSinceEpoch;

        try {
          await AppAnalyticsService.instance.logPaymentAttempt(
            kind: addonsOnly ? 'upgrade' : 'creation',
            leagueId: '',
            leagueName: leagueName,
            provider: 'free',
            currency: plan.currency,
            amount: '0',
            userId: userId,
          );
          await AppAnalyticsService.instance.logPaymentResult(
            kind: addonsOnly ? 'upgrade' : 'creation',
            leagueId: '',
            leagueName: leagueName,
            success: true,
            provider: 'free',
            currency: plan.currency,
            amount: '0',
            receiptId: 'FREE-$now',
            errorMessage: null,
            userId: userId,
          );
        } catch (_) {
          // ignore: best-effort
        }

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

      final totalAmount = _toFlutterwaveAmount(total);

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: 'creation',
        leagueId: '',
        leagueName: leagueName,
        provider: providerName,
        currency: plan.currency,
        amount: totalAmount,
        userId: userId,
      );

      final authUser = FirebaseAuth.instance.currentUser;
      final String email = (authUser?.email?.trim().isNotEmpty ?? false)
          ? authUser!.email!.trim()
          : 'user_$userId@eleaguehub.app';
      final String phone = (authUser?.phoneNumber?.trim().isNotEmpty ?? false)
          ? authUser!.phoneNumber!.trim()
          : '0000000000';
      final String name = (authUser?.displayName?.trim().isNotEmpty ?? false)
          ? authUser!.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final txRef = addonsOnly
          ? 'EH-UPG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}'
          : 'EH-CRT-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final couponsPart = buyCouponsForParticipants
          ? ' + coupons: $safeCouponCount (discount $discountPercent%)'
          : '';

      final action = addonsOnly ? 'League upgrade' : 'League creation';
      final description = '$action$couponsPart: $leagueName';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: plan.currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: 'card,ussd,banktransfer',
        customization: Customization(
          title: 'EleagueHub',
          description: description,
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (response.success == true) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final receipt = (response.transactionId != null && '${response.transactionId}'.trim().isNotEmpty)
            ? 'FLW-${response.transactionId}'
            : (response.txRef?.trim().isNotEmpty ?? false)
                ? 'FLW-${response.txRef}'
                : 'FLW-$txRef';

        await AppAnalyticsService.instance.logPaymentResult(
          kind: 'creation',
          leagueId: '',
          leagueName: leagueName,
          success: true,
          provider: providerName,
          currency: plan.currency,
          amount: totalAmount,
          receiptId: receipt,
          errorMessage: null,
          userId: userId,
        );

        return LeagueCreationPaymentResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: providerName,
          viewerCapacity: 0,
          buyCouponsForParticipants: buyCouponsForParticipants,
          couponDiscountPercent: discountPercent,
          couponCount: safeCouponCount,
          totalAmount: totalAmount,
        );
      }

      await AppAnalyticsService.instance.logPaymentResult(
        kind: 'creation',
        leagueId: '',
        leagueName: leagueName,
        success: false,
        provider: providerName,
        currency: plan.currency,
        amount: totalAmount,
        receiptId: null,
        errorMessage: 'Payment cancelled or not successful',
        userId: userId,
      );

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
      try {
        final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));
        await AppAnalyticsService.instance.logPaymentResult(
          kind: 'creation',
          leagueId: '',
          leagueName: leagueName,
          success: false,
          provider: providerName,
          currency: plan.currency,
          amount: '0',
          receiptId: null,
          errorMessage: e.toString(),
          userId: userId,
        );
      } catch (_) {
        // ignore: best-effort
      }

      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
        viewerCapacity: 0,
        buyCouponsForParticipants: buyCouponsForParticipants,
        couponDiscountPercent: discountPercent,
        couponCount: safeCouponCount,
        totalAmount: '0',
      );
    }
  }
}
