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

  /// OPTIONAL add-on: viewer capacity purchased at creation time.
  /// 0 means not enabled.
  final int viewerCapacity;

  /// OPTIONAL add-on: organizer purchased coupons for participants.
  /// If true, backend should generate league-specific coupons after:
  /// - successful payment
  /// - league creation
  final bool buyCouponsForParticipants;

  /// Coupon discount as percentage off the league join/access charge.
  /// 0 means coupons not enabled.
  /// 100 means free access.
  final int couponDiscountPercent;

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
    required this.totalAmount,
  });

  factory LeagueCreationPaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required int viewerCapacity,
    required bool buyCouponsForParticipants,
    required int couponDiscountPercent,
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
      totalAmount: totalAmount,
    );
  }

  factory LeagueCreationPaymentResult.failed({
    required String provider,
    required String errorMessage,
    int viewerCapacity = 0,
    bool buyCouponsForParticipants = false,
    int couponDiscountPercent = 0,
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
      totalAmount: totalAmount,
    );
  }
}

abstract class LeagueCreationPaymentService {
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,

    /// OPTIONAL paid add-on (viewers are separate from participants).
    int viewerCapacity,

    /// OPTIONAL add-on: buy coupons for participants (generated after payment+league creation).
    bool buyCouponsForParticipants,

    /// OPTIONAL add-on: coupon percent discount (0=disabled, 100=free).
    int couponDiscountPercent,
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
    // Minimum 1% doesn't match UI; enforce UI constraints on backend-facing values anyway.
    if (rawPercent < 5) return 5;
    if (rawPercent > 90) return 90;
    return rawPercent;
  }

  @override
  Future<LeagueCreationPaymentResult> collectLeagueCreationFee({
    required BuildContext context,
    required String userId,
    required String leagueName,
    int viewerCapacity = 0,
    bool buyCouponsForParticipants = false,
    int couponDiscountPercent = 0,
  }) async {
    final safeViewerCapacity = viewerCapacity < 0 ? 0 : viewerCapacity;
    final safeCouponPercent = _sanitizeCouponPercent(buyCouponsForParticipants, couponDiscountPercent);

    try {
      FlutterwaveConfig.assertConfigured();

      final locale = Localizations.maybeLocaleOf(context);
      final pricing = FlutterwaveConfig.pricingForLocale(locale);
      FlutterwaveConfig.assertValidPricing(pricing);

      final base = double.tryParse(pricing.createLeagueAmount.trim()) ?? 0;
      final unit = double.tryParse(pricing.viewLeagueAmount.trim()) ?? 0;

      final total = base + (safeViewerCapacity * unit);
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

      final txRef = 'EH-CRT-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final couponsPart = buyCouponsForParticipants
          ? (safeCouponPercent >= 100
              ? ' + coupons (free access)'
              : ' + coupons (${safeCouponPercent}% discount)')
          : '';

      final description = safeViewerCapacity > 0
          ? 'League creation + viewers ($safeViewerCapacity)$couponsPart: $leagueName'
          : 'League creation charges$couponsPart: $leagueName';

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

      // flutterwave_standard 1.1.0 requires BuildContext in charge()
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
          totalAmount: totalAmount,
        );
      }

      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        viewerCapacity: safeViewerCapacity,
        buyCouponsForParticipants: buyCouponsForParticipants,
        couponDiscountPercent: safeCouponPercent,
        totalAmount: totalAmount,
      );
    } catch (e) {
      return LeagueCreationPaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
        viewerCapacity: safeViewerCapacity,
        buyCouponsForParticipants: buyCouponsForParticipants,
        couponDiscountPercent: safeCouponPercent,
        totalAmount: '0',
      );
    }
  }
}
