import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';

final leagueChargesPaymentServiceProvider = Provider<LeagueChargesPaymentService>((ref) {
  return FlutterwaveLeagueChargesPaymentService();
});

class LeagueChargesPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

  /// Amount charged (Flutterwave string format).
  final String totalAmount;

  const LeagueChargesPaymentResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.totalAmount,
  });

  factory LeagueChargesPaymentResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required String totalAmount,
  }) {
    return LeagueChargesPaymentResult._(
      success: true,
      receiptId: receiptId,
      paidAtMs: paidAtMs,
      provider: provider,
      errorMessage: null,
      totalAmount: totalAmount,
    );
  }

  factory LeagueChargesPaymentResult.failed({
    required String provider,
    required String errorMessage,
    String totalAmount = '0',
  }) {
    return LeagueChargesPaymentResult._(
      success: false,
      receiptId: null,
      paidAtMs: 0,
      provider: provider,
      errorMessage: errorMessage,
      totalAmount: totalAmount,
    );
  }
}

abstract class LeagueChargesPaymentService {
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,

    /// OPTIONAL: override amount (used for coupon discounts).
    /// If null/empty, defaults to FlutterwaveConfig viewLeagueAmount.
    String? amountOverride,

    /// OPTIONAL: included only in the payment description for traceability.
    String? couponCode,

    /// OPTIONAL: included only in the payment description for traceability.
    int? couponDiscountPercent,
  });

  String get providerName;
}

class FlutterwaveLeagueChargesPaymentService implements LeagueChargesPaymentService {
  final Uuid _uuid = const Uuid();

  @override
  String get providerName => 'flutterwave';

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  String _normalizeAmount(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '0';

    final d = double.tryParse(trimmed);
    if (d == null) return '0';
    if (d <= 0) return '0';

    return _toFlutterwaveAmount(d);
  }

  @override
  Future<LeagueChargesPaymentResult> payLeagueCharges({
    required BuildContext context,
    required String userId,
    required String leagueId,
    required String leagueName,
    String? amountOverride,
    String? couponCode,
    int? couponDiscountPercent,
  }) async {
    try {
      FlutterwaveConfig.assertConfigured();

      final locale = Localizations.maybeLocaleOf(context);
      final pricing = FlutterwaveConfig.pricingForLocale(locale);
      FlutterwaveConfig.assertValidPricing(pricing);

      final defaultAmount = _normalizeAmount(pricing.viewLeagueAmount);
      final overrideNormalized = (amountOverride != null && amountOverride.trim().isNotEmpty)
          ? _normalizeAmount(amountOverride)
          : '';

      final totalAmount = (overrideNormalized.isNotEmpty && overrideNormalized != '0') ? overrideNormalized : defaultAmount;

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

      final txRef = 'EH-CHG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final cpn = (couponCode ?? '').trim().toUpperCase();
      final int pct = (couponDiscountPercent ?? 0) < 0 ? 0 : (couponDiscountPercent ?? 0);

      final couponPart = (cpn.isNotEmpty && pct > 0) ? ' (coupon $cpn: ${pct}%)' : '';

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
          description: 'League charges$couponPart: $leagueName',
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

        return LeagueChargesPaymentResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: providerName,
          totalAmount: totalAmount,
        );
      }

      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        totalAmount: totalAmount,
      );
    } catch (e) {
      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
        totalAmount: '0',
      );
    }
  }
}
