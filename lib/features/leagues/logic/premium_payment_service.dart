import 'package:cloud_firestore/cloud_firestore.dart';
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

final premiumPaymentServiceProvider = Provider<PremiumPaymentService>((ref) {
  return PremiumPaymentService();
});

class PremiumPurchaseResult {
  final bool success;
  final String? receiptId;
  final int paidAtMs;
  final String provider;
  final String? errorMessage;
  final int premiumDurationDays;

  const PremiumPurchaseResult._({
    required this.success,
    required this.receiptId,
    required this.paidAtMs,
    required this.provider,
    required this.errorMessage,
    required this.premiumDurationDays,
  });

  factory PremiumPurchaseResult.paid({
    required String receiptId,
    required int paidAtMs,
    required String provider,
    required int premiumDurationDays,
  }) =>
      PremiumPurchaseResult._(
        success: true,
        receiptId: receiptId,
        paidAtMs: paidAtMs,
        provider: provider,
        errorMessage: null,
        premiumDurationDays: premiumDurationDays,
      );

  factory PremiumPurchaseResult.failed({
    required String provider,
    required String errorMessage,
  }) =>
      PremiumPurchaseResult._(
        success: false,
        receiptId: null,
        paidAtMs: 0,
        provider: provider,
        errorMessage: errorMessage,
        premiumDurationDays: 0,
      );
}

class PremiumPaymentService {
  final Uuid _uuid = const Uuid();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _providerName => 'flutterwave';

  String _toFlutterwaveAmount(double v) {
    final rounded = double.parse(v.toStringAsFixed(2));
    final intVal = rounded.toInt();
    if ((rounded - intVal).abs() < 0.000001) return '$intVal';
    return rounded.toStringAsFixed(2);
  }

  Future<PremiumPurchaseResult> purchasePremium({
    required BuildContext context,
    required String userId,
  }) async {
    String attemptId = '';

    try {
      final plan = await RemotePricingService.instance.getPlanForLocale(Localizations.maybeLocaleOf(context));

      if (!plan.premiumEnabled) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _writePremiumToFirestore(
          userId: userId,
          durationDays: plan.premiumDurationDays,
          receiptId: 'FREE-DISABLED-$now',
          provider: 'free',
        );
        return PremiumPurchaseResult.paid(
          receiptId: 'FREE-DISABLED-$now',
          paidAtMs: now,
          provider: 'free',
          premiumDurationDays: plan.premiumDurationDays,
        );
      }

      FlutterwaveConfig.assertConfigured();

      final totalAmount = _toFlutterwaveAmount(plan.premiumFee);

      attemptId = await PaymentsService.instance.createAttempt(
        PaymentAttemptCreate(
          provider: _providerName,
          currency: plan.currency,
          amount: plan.premiumFee,
          amountStr: totalAmount,
          userId: FirebaseAuth.instance.currentUser!.uid,
          leagueId: '',
          leagueName: 'App Unlock',
          items: [
            PaymentLineItem(
              productType: 'appUnlock',
              productSubType: 'premium_subscription',
              quantity: 1,
              amount: plan.premiumFee,
            ),
          ],
        ),
      );

      try {
        await AppAnalyticsService.instance.logPaymentAttempt(
          kind: 'appUnlock',
          leagueId: '',
          leagueName: 'App Unlock',
          provider: _providerName,
          currency: plan.currency,
          amount: totalAmount,
          userId: userId,
        );
      } catch (_) {}

      final txRef = 'EH-PRM-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      final authUser = FirebaseAuth.instance.currentUser;
      final email = (authUser?.email?.trim().isNotEmpty ?? false) ? authUser!.email!.trim() : 'user_$userId@eleaguehub.app';
      final phone = (authUser?.phoneNumber?.trim().isNotEmpty ?? false) ? authUser!.phoneNumber!.trim() : '0000000000';
      final name = (authUser?.displayName?.trim().isNotEmpty ?? false) ? authUser!.displayName!.trim() : 'EleagueHub User';

      final customer = Customer(name: name, phoneNumber: phone, email: email);

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: plan.currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: plan.currency.toUpperCase() == 'NGN' ? 'card,ussd,banktransfer' : 'card',
        customization: Customization(
          title: 'EleagueHub',
          description: 'Premium subscription — ${plan.premiumDurationDays} days',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (response.success == true) {
        final txId = (response.transactionId ?? '').toString().trim();
        if (txId.isEmpty) {
          await PaymentsService.instance.markClientFailed(attemptId: attemptId, errorMessage: 'Missing transactionId.');
          return PremiumPurchaseResult.failed(provider: _providerName, errorMessage: 'Missing transaction id.');
        }

        final resolvedTxRef = (response.txRef?.trim().isNotEmpty ?? false) ? response.txRef!.trim() : txRef;

        final recorded = await PaymentsService.instance.recordFlutterwaveClientSuccess(
          attemptId: attemptId,
          transactionId: txId,
          txRef: resolvedTxRef,
        );

        await _writePremiumToFirestore(
          userId: userId,
          durationDays: plan.premiumDurationDays,
          receiptId: recorded.receiptId,
          provider: _providerName,
        );

        return PremiumPurchaseResult.paid(
          receiptId: recorded.receiptId,
          paidAtMs: recorded.paidAtMs,
          provider: _providerName,
          premiumDurationDays: plan.premiumDurationDays,
        );
      }

      if (attemptId.isNotEmpty) {
        await PaymentsService.instance.markClientCancelled(attemptId: attemptId, reason: 'Payment cancelled or not successful');
      }

      return PremiumPurchaseResult.failed(
        provider: _providerName,
        errorMessage: 'Payment cancelled or not successful',
      );
    } catch (e) {
      if (attemptId.isNotEmpty) {
        try {
          await PaymentsService.instance.markClientFailed(attemptId: attemptId, errorMessage: e.toString());
        } catch (_) {}
      }

      return PremiumPurchaseResult.failed(
        provider: _providerName,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _writePremiumToFirestore({
    required String userId,
    required int durationDays,
    required String receiptId,
    required String provider,
  }) async {
    final expiresAt = DateTime.now().add(Duration(days: durationDays)).millisecondsSinceEpoch;

    await _firestore.collection('users').doc(userId).update({
      'isPremium': true,
      'premiumExpiresAtMs': expiresAt,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 20));
  }
}
