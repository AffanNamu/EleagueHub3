import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';

final leagueCreationPaymentServiceProvider = Provider<LeagueCreationPaymentService>((ref) {
  return FlutterwaveLeagueCreationPaymentService();
});

class LeagueCreationPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

  /// OPTIONAL add-on: viewer capacity purchased at creation time (or upgrade time).
  /// 0 means not enabled.
  final int viewerCapacity;

  /// OPTIONAL add-on: organizer purchased coupons for participants/viewers.
  final bool buyCouponsForParticipants;

  /// Coupon discount as percentage off the league join/access charge.
  /// 0 means coupons not enabled.
  /// 100 means free access.
  final int couponDiscountPercent;

  /// OPTIONAL: how many coupons the organizer wants generated/covered at purchase time.
  /// 0 means none.
  final int couponCount;

  /// Amount charged (Flutterwave string format).
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
      couponDiscountPercent: couponDiscountPercent,
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
      couponDiscountPercent: couponDiscountPercent,
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

    /// When true, do NOT charge the base "createLeagueAmount".
    /// This is used for purchasing add-ons for an existing league (upgrade).
    bool addonsOnly,

    /// OPTIONAL paid add-on (viewers are separate from participants).
    int viewerCapacity,

    /// OPTIONAL add-on: buy coupons for participants/viewers (generated after payment+sync).
    bool buyCouponsForParticipants,

    /// OPTIONAL add-on: coupon percent discount (0=disabled, 100=free).
    int couponDiscountPercent,

    /// OPTIONAL add-on: coupon quantity to include/generate.
    int couponCount,
  });

  String get providerName;
}

class FlutterwaveLeagueCreationPaymentService implements LeagueCreationPaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

  String _toFlutterwaveAmount(double v) {
    // Flutterwave accepts string numbers; keep it clean.
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    // Avoid locale commas, etc.
    return rounded.toStringAsFixed(2);
  }

  int _sanitizeCouponPercent(bool enabled, int rawPercent) {
    if (!enabled) return 0;
    if (rawPercent >= 100) return 100;
    if (rawPercent < 5) return 5;
    if (rawPercent > 90) return 90;
    return rawPercent;
  }

  int _sanitizeCount(int v) => v < 0 ? 0 : v;

  double _discountedAddon({
    required double unitPrice,
    required int count,
  }) {
    final c = _sanitizeCount(count);
    if (c <= 0) return 0;

    final raw = unitPrice * c;

    // Rule: if buyer buys above 100 viewers/coupons => 20% discount on that portion.
    if (c > 100) {
      return raw * 0.8;
    }
    return raw;
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
    final safeViewerCapacity = _sanitizeCount(viewerCapacity);
    final safeCouponCount = buyCouponsForParticipants ? _sanitizeCount(couponCount) : 0;
    final safeCouponPercent = _sanitizeCouponPercent(buyCouponsForParticipants, couponDiscountPercent);

    try {
      FlutterwaveConfig.assertConfigured();

      final locale = Localizations.maybeLocaleOf(context);
      final pricing = FlutterwaveConfig.pricingForLocale(locale);
      FlutterwaveConfig.assertValidPricing(pricing);

      // addonsOnly (upgrade): base fee is 0.
      final base = addonsOnly ? 0 : (double.tryParse(pricing.createLeagueAmount.trim()) ?? 0);

      // Viewer unit price and coupon unit price are the same, as requested.
      final unit = double.tryParse(pricing.viewLeagueAmount.trim()) ?? 0;

      final viewersAddon = _discountedAddon(unitPrice: unit, count: safeViewerCapacity);
      final couponsAddon = _discountedAddon(unitPrice: unit, count: safeCouponCount);

      final total = base + viewersAddon + couponsAddon;
      final totalAmount = _toFlutterwaveAmount(total);

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

      final viewersPart = safeViewerCapacity > 0 ? ' + viewers ($safeViewerCapacity)' : '';
      final couponsPart = buyCouponsForParticipants
          ? (safeCouponCount > 0
              ? (safeCouponPercent >= 100
                  ? ' + coupons ($safeCouponCount, free access)'
                  : ' + coupons ($safeCouponCount, ${safeCouponPercent}% discount)')
              : (safeCouponPercent >= 100 ? ' + coupons (free access)' : ' + coupons (${safeCouponPercent}% discount)'))
          : '';

      final action = addonsOnly ? 'League upgrade' : 'League creation';
      final description = '$action$viewersPart$couponsPart: $leagueName';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: pricing.currency,
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

        return LeagueCreationPaymentResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: providerName,
          viewerCapacity: safeViewerCapacity,
          buyCouponsForParticipants: buyCouponsForParticipants,
          couponDiscountPercent: safeCouponPercent,
          couponCount: safeCouponCount,
          totalAmount: totalAmount,
        );
      }

      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        viewerCapacity: safeViewerCapacity,
        buyCouponsForParticipants: buyCouponsForParticipants,
        couponDiscountPercent: safeCouponPercent,
        couponCount: safeCouponCount,
        totalAmount: totalAmount,
      );
    } catch (e) {
      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
        viewerCapacity: safeViewerCapacity,
        buyCouponsForParticipants: buyCouponsForParticipants,
        couponDiscountPercent: safeCouponPercent,
        couponCount: safeCouponCount,
        totalAmount: '0',
      );
    }
  }
}
