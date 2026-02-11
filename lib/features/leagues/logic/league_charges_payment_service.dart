import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/app_analytics_service.dart';
import '../../../core/services/remote_pricing_service.dart';

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

    /// OPTIONAL: override amount (used for coupon redemptions).
    /// If null/empty, defaults to access fee from RemotePricingService.
    String? amountOverride,

    /// OPTIONAL: included only in the payment description for traceability.
    String? couponCode,

    /// OPTIONAL: included only in the payment description for traceability.
    int? couponDiscountPercent,

    /// OPTIONAL: force a specific currency (e.g., 'NGN' or 'USD') for this charge.
    /// Use this for coupon redemptions to match the couponConfig currency.
    String? currencyOverride,
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

  String _resolvedCurrency({required String planCurrency, String? override}) {
    final o = (override ?? '').trim().toUpperCase();
    if (o == 'NGN' || o == 'USD') return o;
    return planCurrency;
  }

  String _resolveEffectiveUserId(String userId) {
    final u = userId.trim();
    if (u.isNotEmpty) return u;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.trim().isNotEmpty) return authUid.trim();
    return 'anonymous';
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
    String? currencyOverride,
  }) async {
    String currencyUsed = '';
    String totalAmount = '0';
    String analyticsKind = 'access';

    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
      FlutterwaveConfig.assertConfigured();

      // Resolve runtime pricing and default currency from Firestore (server-driven config).
      final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));
      final currency = _resolvedCurrency(planCurrency: plan.currency, override: currencyOverride);
      currencyUsed = currency;

      final defaultAmount = _toFlutterwaveAmount(plan.accessFee);
      final overrideNormalized = (amountOverride != null && amountOverride.trim().isNotEmpty)
          ? _normalizeAmount(amountOverride)
          : '';

      totalAmount = (overrideNormalized.isNotEmpty && overrideNormalized != '0') ? overrideNormalized : defaultAmount;

      // Determine analytics kind
      final cpn = (couponCode ?? '').trim().toUpperCase();
      analyticsKind = cpn.isNotEmpty ? 'redemption' : 'access';
      final int pct = (couponDiscountPercent ?? 0) < 0 ? 0 : (couponDiscountPercent ?? 0);

      // Log attempt (best-effort). Analytics service stores userId as auth uid; actor id goes to actorUserId.
      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: analyticsKind,
        leagueId: leagueId,
        leagueName: leagueName,
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        userId: effectiveUserId,
      );

      final String email = (FirebaseAuth.instance.currentUser?.email?.trim().isNotEmpty ?? false)
          ? FirebaseAuth.instance.currentUser!.email!.trim()
          : 'user_$effectiveUserId@eleaguehub.app';
      final String phone = (FirebaseAuth.instance.currentUser?.phoneNumber?.trim().isNotEmpty ?? false)
          ? FirebaseAuth.instance.currentUser!.phoneNumber!.trim()
          : '0000000000';
      final String name = (FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ?? false)
          ? FirebaseAuth.instance.currentUser!.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final txRef = 'EH-CHG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final couponPart = (cpn.isNotEmpty && pct > 0)
          ? ' (coupon $cpn: ${pct}%)'
          : (cpn.isNotEmpty ? ' (coupon $cpn)' : '');

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currencyUsed,
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

        await AppAnalyticsService.instance.logPaymentResult(
          kind: analyticsKind,
          leagueId: leagueId,
          leagueName: leagueName,
          success: true,
          provider: providerName,
          currency: currencyUsed,
          amount: totalAmount,
          receiptId: receipt,
          errorMessage: null,
          userId: effectiveUserId,
        );

        return LeagueChargesPaymentResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: providerName,
          totalAmount: totalAmount,
        );
      }

      await AppAnalyticsService.instance.logPaymentResult(
        kind: analyticsKind,
        leagueId: leagueId,
        leagueName: leagueName,
        success: false,
        provider: providerName,
        currency: currencyUsed,
        amount: totalAmount,
        receiptId: null,
        errorMessage: 'Payment cancelled or not successful',
        userId: effectiveUserId,
      );

      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        totalAmount: totalAmount,
      );
    } catch (e) {
      try {
        if (currencyUsed.isEmpty) {
          final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));
          currencyUsed = _resolvedCurrency(planCurrency: plan.currency, override: currencyOverride);
        }
        await AppAnalyticsService.instance.logPaymentResult(
          kind: analyticsKind,
          leagueId: leagueId,
          leagueName: leagueName,
          success: false,
          provider: providerName,
          currency: currencyUsed,
          amount: totalAmount,
          receiptId: null,
          errorMessage: e.toString(),
          userId: effectiveUserId,
        );
      } catch (_) {
        // ignore: best-effort
      }

      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
        totalAmount: totalAmount,
      );
    }
  }
}
