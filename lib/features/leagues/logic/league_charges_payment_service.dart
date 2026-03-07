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
import 'league_charges_store.dart';

final leagueChargesPaymentServiceProvider = Provider<LeagueChargesPaymentService>((ref) {
  return FlutterwaveLeagueChargesPaymentService();
});

class LeagueChargesPaymentResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;

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
    String? amountOverride,
    String? couponCode,
    int? couponDiscountPercent,
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
    String attemptId = '';

    final effectiveUserId = _resolveEffectiveUserId(userId);

    try {
      FlutterwaveConfig.assertConfigured();

      final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));
      currencyUsed = _resolvedCurrency(planCurrency: plan.currency, override: currencyOverride);

      final defaultAmount = _toFlutterwaveAmount(plan.accessFee);
      final overrideNormalized = (amountOverride != null && amountOverride.trim().isNotEmpty) ? _normalizeAmount(amountOverride) : '';
      totalAmount = (overrideNormalized.isNotEmpty && overrideNormalized != '0') ? overrideNormalized : defaultAmount;

      final cpn = (couponCode ?? '').trim().toUpperCase();
      final kind = cpn.isNotEmpty ? 'coupon_redemption' : 'league_access';
      final numericAmount = double.tryParse(totalAmount) ?? 0.0;

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: providerName,
          currency: currencyUsed,
          amount: numericAmount,
          amountStr: totalAmount,
          userId: FirebaseAuth.instance.currentUser!.uid,
          leagueId: leagueId,
          leagueName: leagueName,
          couponCode: cpn,
          items: [
            PaymentLineItem(
              productType: 'league',
              productSubType: kind,
              quantity: 1,
              amount: numericAmount,
            ),
          ],
        ),
      );

      await AppAnalyticsService.instance.logPaymentAttempt(
        kind: kind,
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

      final customer = Customer(name: name, phoneNumber: phone, email: email);

      final txRef = 'EH-CHG-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: currencyUsed,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: currencyUsed.toUpperCase() == 'NGN' ? 'card,ussd,banktransfer' : 'card',
        customization: Customization(
          title: 'EleagueHub',
          description: 'League charges: $leagueName',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (response.success == true) {
        final txId = (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          await PaymentsService.instance.markClientFailed(attemptId: attemptId, errorMessage: 'Missing transactionId.');
          return LeagueChargesPaymentResult.failed(provider: providerName, errorMessage: 'Missing transaction id.', totalAmount: totalAmount);
        }

        final resolvedTxRef = (response.txRef?.trim().isNotEmpty ?? false) ? response.txRef!.trim() : txRef;

        final recorded = await PaymentsService.instance.recordFlutterwaveClientSuccess(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        // Store receipt for access gating
        try {
          await LeagueChargesStore.online().storeReceipt(
            LeagueChargesReceipt(
              leagueId: leagueId,
              userId: FirebaseAuth.instance.currentUser!.uid,
              receiptId: recorded.receiptId,
              provider: providerName,
              paidAtMs: recorded.paidAtMs,
            ),
          );
        } catch (_) {}

        return LeagueChargesPaymentResult.paid(
          receiptId: recorded.receiptId,
          paidAtMs: recorded.paidAtMs,
          provider: providerName,
          totalAmount: totalAmount,
        );
      }

      await PaymentsService.instance.markClientCancelled(attemptId: attemptId, reason: 'Payment cancelled or not successful');

      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: 'Payment cancelled or not successful',
        totalAmount: totalAmount,
      );
    } catch (e) {
      if (attemptId.isNotEmpty) {
        try {
          await PaymentsService.instance.markClientFailed(attemptId: attemptId, errorMessage: e.toString());
        } catch (_) {}
      }

      return LeagueChargesPaymentResult.failed(
        provider: providerName,
        errorMessage: e.toString(),
        totalAmount: totalAmount,
      );
    }
  }
}
