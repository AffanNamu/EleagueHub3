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
  // Viewers are fully removed from pricing; this stays 0.
  final int viewerCapacity;

  // Coupons were enabled as an add-on during creation time (still supported).
  final bool buyCouponsForParticipants;

  // IMPORTANT (new semantics):
  // couponDiscountPercent now stores DISCOUNT percent (0..100) that users get at redemption time.
  // 100% means free access, 0% means no discount.
  final int couponDiscountPercent;

  // How many coupons organizer wants to buy.
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

    // When true, do NOT charge the base creation fee.
    // This is used for purchasing add-ons for an existing league (upgrade).
    bool addonsOnly,

    // DEPRECATED: viewers are removed. This parameter is ignored (kept for compatibility).
    int viewerCapacity,

    // OPTIONAL add-on: buy coupons for participants (single configuration per league).
    bool buyCouponsForParticipants,

    // IMPORTANT (new semantics):
    // DISCOUNT percent for users at redemption (0..100).
    int couponDiscountPercent,

    // OPTIONAL add-on: coupon quantity to purchase.
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

  @override
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
    bool addonsOnly = false,
    int viewerCapacity = 0, // ignored
    bool buyCouponsForParticipants = false,
    int couponDiscountPercent = 0, // DISCOUNT percent
    int couponCount = 0,
  }) async {
    final safeCouponCount = buyCouponsForParticipants ? _sanitizeCount(couponCount) : 0;
    final discountPercent = _sanitizePercent(couponDiscountPercent);

    try {
      FlutterwaveConfig.assertConfigured();

      // Resolve pricing from Firestore (with safe defaults).
      final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));

      // Base fee: required unless this is an upgrade purchase.
      final base = addonsOnly ? 0.0 : plan.createLeagueFee;

      // Coupon add-on (organizer ALWAYS pays full coupon subtotal; only bulk discount may apply).
      final couponSubtotalDiscounted = buyCouponsForParticipants
          ? RemotePricingService.instance.couponSubtotalWithThresholdDiscount(
              plan: plan,
              couponCount: safeCouponCount,
            )
          : 0.0;

      // NEW: no subsidy split. Organizer pays all coupon cost.
      final total = base + couponSubtotalDiscounted;
      final totalAmount = _toFlutterwaveAmount(total);

      // Log attempt (best-effort)
      // No leagueId yet at creation time → leave empty string.
      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: 'creation',
        leagueId: '',
        leagueName: leagueName,
        provider: providerName,
        currency: plan.currency,
        amount: totalAmount,
        userId: userId,
      );

      // Build Flutterwave payload
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

        // Log success
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

        // NOTE: viewerCapacity is deprecated => always zero.
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

      // Log failure
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
      // Log failure
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
