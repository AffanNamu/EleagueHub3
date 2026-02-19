import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterwave_standard/flutterwave.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/flutterwave_config.dart';
import '../../../core/services/app_analytics_service.dart';
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

/// Dedicated payment service for premium subscriptions.
///
/// Flow:
///   1. Fetch plan from RemotePricingService (correct currency for locale).
///   2. If premiumEnabled == false → return paid() immediately (free pass).
///   3. Launch Flutterwave charge for plan.premiumFee.
///   4. On Flutterwave success → write isPremium + premiumExpiresAtMs to
///      Firestore using .update() so the Firestore UPDATE rule is satisfied.
///   5. Log analytics attempt + result.
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

  /// Charge the user for premium and, on success, write the Firestore doc.
  Future<PremiumPurchaseResult> purchasePremium({
    required BuildContext context,
    required String userId,
  }) async {
    try {
      final plan = await RemotePricingService.instance
          .getPlanForLocale(Localizations.maybeLocaleOf(context));

      // Super-admin kill-switch: premium feature disabled globally.
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
      final txRef =
          'EH-PRM-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}';

      // Analytics: attempt
      try {
        await AppAnalyticsService.instance.logPaymentAttempt(
          kind: 'premium',
          leagueId: '',
          leagueName: 'Premium Subscription',
          provider: _providerName,
          currency: plan.currency,
          amount: totalAmount,
          userId: userId,
        );
      } catch (_) {
        // best-effort
      }

      final authUser = FirebaseAuth.instance.currentUser;
      final email = (authUser?.email?.trim().isNotEmpty ?? false)
          ? authUser!.email!.trim()
          : 'user_$userId@eleaguehub.app';
      final phone = (authUser?.phoneNumber?.trim().isNotEmpty ?? false)
          ? authUser!.phoneNumber!.trim()
          : '0000000000';
      final name = (authUser?.displayName?.trim().isNotEmpty ?? false)
          ? authUser!.displayName!.trim()
          : 'EleagueHub User';

      final customer = Customer(
        name: name,
        phoneNumber: phone,
        email: email,
      );

      final flutterwave = Flutterwave(
        publicKey: FlutterwaveConfig.publicKey,
        currency: plan.currency,
        redirectUrl: FlutterwaveConfig.redirectUrl,
        txRef: txRef,
        amount: totalAmount,
        customer: customer,
        paymentOptions: 'card,ussd,banktransfer',
        customization: Customization(
          title: 'EleagueHub Premium',
          description:
              'Premium subscription — ${plan.premiumDurationDays} days',
        ),
        isTestMode: FlutterwaveConfig.isTestMode,
      );

      final ChargeResponse response = await flutterwave.charge(context);

      if (response.success == true) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final receipt =
            (response.transactionId != null &&
                    '${response.transactionId}'.trim().isNotEmpty)
                ? 'FLW-${response.transactionId}'
                : (response.txRef?.trim().isNotEmpty ?? false)
                    ? 'FLW-${response.txRef}'
                    : 'FLW-$txRef';

        // Write isPremium to Firestore BEFORE returning to caller.
        await _writePremiumToFirestore(
          userId: userId,
          durationDays: plan.premiumDurationDays,
          receiptId: receipt,
          provider: _providerName,
        );

        // Analytics: success
        try {
          await AppAnalyticsService.instance.logPaymentResult(
            kind: 'premium',
            leagueId: '',
            leagueName: 'Premium Subscription',
            success: true,
            provider: _providerName,
            currency: plan.currency,
            amount: totalAmount,
            receiptId: receipt,
            errorMessage: null,
            userId: userId,
          );
        } catch (_) {
          // best-effort
        }

        return PremiumPurchaseResult.paid(
          receiptId: receipt,
          paidAtMs: now,
          provider: _providerName,
          premiumDurationDays: plan.premiumDurationDays,
        );
      }

      // Payment cancelled / not successful.
      try {
        await AppAnalyticsService.instance.logPaymentResult(
          kind: 'premium',
          leagueId: '',
          leagueName: 'Premium Subscription',
          success: false,
          provider: _providerName,
          currency: plan.currency,
          amount: totalAmount,
          receiptId: null,
          errorMessage: 'Payment cancelled or not successful',
          userId: userId,
        );
      } catch (_) {
        // best-effort
      }

      return PremiumPurchaseResult.failed(
        provider: _providerName,
        errorMessage: 'Payment cancelled or not successful',
      );
    } catch (e) {
      try {
        final plan = await RemotePricingService.instance
            .getPlanForLocale(Localizations.maybeLocaleOf(context));
        await AppAnalyticsService.instance.logPaymentResult(
          kind: 'premium',
          leagueId: '',
          leagueName: 'Premium Subscription',
          success: false,
          provider: _providerName,
          currency: plan.currency,
          amount: '0',
          receiptId: null,
          errorMessage: e.toString(),
          userId: userId,
        );
      } catch (_) {
        // best-effort
      }

      return PremiumPurchaseResult.failed(
        provider: _providerName,
        errorMessage: e.toString(),
      );
    }
  }

  /// Write isPremium=true and premiumExpiresAtMs to the user's Firestore doc.
  ///
  /// Uses .update() so the Firestore UPDATE rule is evaluated (not CREATE).
  /// The rule requires changedKeys to be exactly
  /// ['isPremium', 'premiumExpiresAtMs', 'updatedAt'] and
  /// premiumExpiresAtMs > request.time.toMillis() (future expiry).
  Future<void> _writePremiumToFirestore({
    required String userId,
    required int durationDays,
    required String receiptId,
    required String provider,
  }) async {
    final expiresAt = DateTime.now()
        .add(Duration(days: durationDays))
        .millisecondsSinceEpoch;

    await _firestore
        .collection('users')
        .doc(userId)
        .update({
          'isPremium': true,
          'premiumExpiresAtMs': expiresAt,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }
}
